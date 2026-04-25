import Foundation

final class SettingsViewModel: ObservableObject {
    @Published var apiKey: String
    @Published var modelListText: String
    @Published var selectedModel: String
    @Published var systemPrompt: String
    @Published var shortcut: GlobalKeyboardShortcut
    @Published var agentModeEnabled: Bool
    @Published var isRefreshingModels = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let keychain: KeychainServicing
    private let client: OpenRouterServicing

    init(keychain: KeychainServicing = KeychainService(), client: OpenRouterServicing = OpenRouterClient()) {
        self.keychain = keychain
        self.client = client

        let settings = AppSettings.load()
        self.apiKey = (try? keychain.loadAPIKey()) ?? ""
        self.modelListText = settings.modelIDs.joined(separator: "\n")
        self.selectedModel = settings.selectedModelID
        self.systemPrompt = settings.systemPrompt
        self.shortcut = settings.shortcut
        self.agentModeEnabled = settings.agentModeEnabled
    }

    var parsedModels: [String] {
        AppSettings.normalizedModels(modelListText.components(separatedBy: .newlines))
    }

    func save() {
        errorMessage = nil
        statusMessage = nil

        let models = parsedModels
        if !models.contains(selectedModel) {
            selectedModel = models[0]
        }

        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = AppSettings(
            modelIDs: models,
            selectedModelID: selectedModel,
            systemPrompt: prompt.isEmpty ? Constants.defaultSystemPrompt : systemPrompt,
            shortcut: shortcut,
            agentModeEnabled: agentModeEnabled
        )

        do {
            try keychain.saveAPIKey(apiKey)
            settings.save()
            statusMessage = "Settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetModels() {
        modelListText = Constants.defaultModelIDs.joined(separator: "\n")
        selectedModel = Constants.freeRouterModelID
    }

    @MainActor
    func refreshModelsFromOpenRouter() async {
        guard !isRefreshingModels else {
            return
        }

        isRefreshingModels = true
        errorMessage = nil
        statusMessage = nil
        defer {
            isRefreshingModels = false
        }

        do {
            let models = try await client.fetchModelIDs()
            modelListText = models.joined(separator: "\n")
            if !models.contains(selectedModel) {
                selectedModel = Constants.freeRouterModelID
            }
            statusMessage = "Loaded \(models.count) OpenRouter models."
        } catch {
            errorMessage = "Could not refresh models: \(error.localizedDescription)"
        }
    }
}
