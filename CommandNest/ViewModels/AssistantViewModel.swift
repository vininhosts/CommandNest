import Foundation
import AppKit

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var messages: [ChatMessage]
    @Published var availableModels: [String]
    @Published var selectedModel: String {
        didSet {
            guard !isReloadingPreferences, selectedModel != oldValue else {
                return
            }

            var settings = AppSettings.load()
            settings.selectedModelID = selectedModel
            settings.save()
        }
    }
    @Published private(set) var isSending = false
    @Published private(set) var isRefreshingModels = false
    @Published var errorMessage: String?
    @Published private(set) var agentActivity: [String] = []

    private let client: OpenRouterServicing
    private let agentService: AgentServicing
    private let localActionService: LocalActionServicing
    private let keychain: KeychainServicing
    private var systemPrompt: String
    private var agentModeEnabled: Bool
    private var confirmAgentActions: Bool
    private var isReloadingPreferences = false

    init(
        client: OpenRouterServicing = OpenRouterClient(),
        agentService: AgentServicing = AgentService(),
        localActionService: LocalActionServicing = LocalActionService(),
        keychain: KeychainServicing = KeychainService()
    ) {
        let settings = AppSettings.load()
        self.client = client
        self.agentService = agentService
        self.localActionService = localActionService
        self.keychain = keychain
        self.availableModels = settings.modelIDs
        self.selectedModel = settings.selectedModelID
        self.systemPrompt = settings.systemPrompt
        self.agentModeEnabled = settings.agentModeEnabled
        self.confirmAgentActions = settings.confirmAgentActions
        self.messages = [ChatMessage(role: .system, content: settings.systemPrompt)]
    }

    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    var lastAssistantResponse: String {
        messages.last(where: { $0.role == .assistant })?.content ?? ""
    }

    func reloadPreferences() {
        let settings = AppSettings.load()
        isReloadingPreferences = true
        availableModels = settings.modelIDs
        selectedModel = settings.selectedModelID
        systemPrompt = settings.systemPrompt
        agentModeEnabled = settings.agentModeEnabled
        confirmAgentActions = settings.confirmAgentActions
        isReloadingPreferences = false

        if let systemIndex = messages.firstIndex(where: { $0.role == .system }) {
            messages[systemIndex].content = settings.systemPrompt
        } else {
            messages.insert(ChatMessage(role: .system, content: settings.systemPrompt), at: 0)
        }
    }

    func refreshModelsFromOpenRouter() async {
        guard !isRefreshingModels else {
            return
        }

        isRefreshingModels = true
        defer {
            isRefreshingModels = false
        }

        do {
            let models = try await client.fetchModelIDs()
            var settings = AppSettings.load()
            settings.modelIDs = models
            if !models.contains(settings.selectedModelID) {
                settings.selectedModelID = Constants.freeRouterModelID
            }
            settings.save()
            reloadPreferences()
        } catch {
            errorMessage = "Could not refresh OpenRouter models: \(error.localizedDescription)"
        }
    }

    func sendPrompt() async {
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompt.isEmpty, !isSending else {
            return
        }

        errorMessage = nil
        agentActivity = []

        prompt = ""
        isSending = true

        let userMessage = ChatMessage(role: .user, content: userPrompt)
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(userMessage)
        messages.append(assistantMessage)

        let assistantID = assistantMessage.id
        let requestMessages = messages.filter { $0.id != assistantID }

        do {
            if let localResponse = try await localActionService.handle(
                prompt: userPrompt,
                onEvent: { [weak self] event in
                    self?.recordAgentActivity(event, assistantID: assistantID)
                },
                confirmAction: { [weak self] preview in
                    guard let self else {
                        return false
                    }
                    return await self.confirmLocalAction(preview)
                }
            ) {
                replaceAssistantMessage(assistantID, with: localResponse)
                isSending = false
                return
            }
        } catch {
            removeEmptyAssistantMessage(assistantID)
            errorMessage = error.localizedDescription
            isSending = false
            return
        }

        let apiKey: String
        do {
            guard let savedKey = try keychain.loadAPIKey(),
                  !savedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OpenRouterClientError.missingAPIKey
            }
            apiKey = savedKey
        } catch let error as OpenRouterClientError {
            removeEmptyAssistantMessage(assistantID)
            errorMessage = error.localizedDescription
            isSending = false
            return
        } catch {
            removeEmptyAssistantMessage(assistantID)
            errorMessage = error.localizedDescription
            isSending = false
            return
        }

        if agentModeEnabled && Self.shouldUseLocalAgent(for: userPrompt) {
            await sendAgentPrompt(apiKey: apiKey, model: selectedModel, requestMessages: requestMessages, assistantID: assistantID)
            isSending = false
            return
        }

        var receivedStreamingChunk = false

        do {
            for try await chunk in client.streamChat(apiKey: apiKey, model: selectedModel, messages: requestMessages) {
                receivedStreamingChunk = true
                append(chunk, toAssistantMessage: assistantID)
            }

            if !receivedStreamingChunk {
                let fullResponse = try await client.completeChat(apiKey: apiKey, model: selectedModel, messages: requestMessages)
                replaceAssistantMessage(assistantID, with: fullResponse)
            }
        } catch {
            if receivedStreamingChunk {
                errorMessage = "\(error.localizedDescription) Partial response was preserved."
            } else {
                do {
                    let fullResponse = try await client.completeChat(apiKey: apiKey, model: selectedModel, messages: requestMessages)
                    replaceAssistantMessage(assistantID, with: fullResponse)
                } catch {
                    removeEmptyAssistantMessage(assistantID)
                    errorMessage = error.localizedDescription
                }
            }
        }

        isSending = false
    }

    func clearConversation() {
        prompt = ""
        errorMessage = nil
        messages = [ChatMessage(role: .system, content: systemPrompt)]
    }

    func copyLastResponse() {
        let response = lastAssistantResponse
        guard !response.isEmpty else {
            return
        }

        ClipboardHelper.copy(response)
    }

    private func append(_ chunk: String, toAssistantMessage id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        messages[index].content += chunk
    }

    private func replaceAssistantMessage(_ id: UUID, with content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        messages[index].content = content
    }

    private func removeEmptyAssistantMessage(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        messages.remove(at: index)
    }

    private func sendAgentPrompt(apiKey: String, model: String, requestMessages: [ChatMessage], assistantID: UUID) async {
        replaceAssistantMessage(assistantID, with: "Starting local agent...")
        agentActivity = ["Starting local agent"]

        do {
            let response = try await agentService.run(
                apiKey: apiKey,
                model: model,
                messages: requestMessages,
                onToolEvent: { [weak self] event in
                    self?.recordAgentActivity(event, assistantID: assistantID)
                },
                confirmTool: { [weak self] preview in
                    guard let self else {
                        return false
                    }
                    return await self.confirmAgentTool(preview)
                }
            )
            replaceAssistantMessage(assistantID, with: response)
        } catch {
            removeEmptyAssistantMessage(assistantID)
            errorMessage = error.localizedDescription
        }
    }

    private func recordAgentActivity(_ event: String, assistantID: UUID) {
        agentActivity.append(event)
        replaceAssistantMessage(assistantID, with: formattedAgentProgress())
    }

    private func formattedAgentProgress() -> String {
        let rows = agentActivity.suffix(12).map { "- \($0)" }.joined(separator: "\n")
        return "Local agent is working...\n\n\(rows)"
    }

    private func confirmLocalAction(_ preview: LocalActionPreview) async -> Bool {
        guard confirmAgentActions else {
            return true
        }

        return presentActionConfirmation(
            title: preview.title,
            detail: preview.detail,
            isDestructive: preview.isDestructive
        )
    }

    private func confirmAgentTool(_ preview: AgentToolPreview) async -> Bool {
        guard confirmAgentActions && preview.requiresConfirmation else {
            return true
        }

        return presentActionConfirmation(
            title: preview.title,
            detail: preview.detail,
            isDestructive: preview.requiresConfirmation
        )
    }

    private func presentActionConfirmation(title: String, detail: String, isDestructive: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow \(title)?"
        alert.informativeText = detail
        alert.alertStyle = isDestructive ? .warning : .informational
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func shouldUseLocalAgent(for prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        let actionWords = [
            "create", "make", "write", "edit", "modify", "change", "organize",
            "organise", "move", "rename", "delete", "trash", "copy", "read",
            "list", "show", "find", "search", "inspect", "open", "run",
            "execute", "install", "build", "test", "fix", "debug"
        ]
        let localTargets = [
            "file", "files", "folder", "folders", "directory", "directories",
            "downloads", "desktop", "documents", "project", "app", "code",
            "terminal", "command", "script", "repo", "repository", ".swift",
            ".md", ".txt", "~/", "/users/"
        ]

        if normalized.contains("on my mac")
            || normalized.contains("my computer")
            || normalized.contains("this mac")
            || normalized.contains("local machine") {
            return true
        }

        return actionWords.contains { normalized.contains($0) }
            && localTargets.contains { normalized.contains($0) }
    }
}
