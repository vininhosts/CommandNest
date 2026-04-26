import AppKit
import Foundation

protocol AgentServicing {
    func run(
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        onToolEvent: @escaping @MainActor (String) -> Void,
        confirmTool: @escaping @MainActor (AgentToolPreview) async -> Bool
    ) async throws -> String
}

struct AgentToolPreview: Equatable {
    let toolName: String
    let title: String
    let detail: String
    let requiresConfirmation: Bool
}

enum AgentServiceError: LocalizedError {
    case invalidToolArguments(String)
    case unknownTool(String)
    case commandTimedOut
    case missingPath
    case blockedShellCommand

    var errorDescription: String? {
        switch self {
        case .invalidToolArguments(let message):
            return "Invalid tool arguments: \(message)"
        case .unknownTool(let name):
            return "Unknown local agent tool: \(name)"
        case .commandTimedOut:
            return "The shell command timed out."
        case .missingPath:
            return "The requested path does not exist."
        case .blockedShellCommand:
            return "CommandNest refused to run a shell command that appears to target the system destructively."
        }
    }
}

final class AgentService: AgentServicing {
    private let client: OpenRouterServicing
    private let maxToolRounds = 8
    private let maxToolOutputCharacters = 24_000

    init(client: OpenRouterServicing = OpenRouterClient()) {
        self.client = client
    }

    func run(
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        onToolEvent: @escaping @MainActor (String) -> Void,
        confirmTool: @escaping @MainActor (AgentToolPreview) async -> Bool
    ) async throws -> String {
        var payloadMessages = messages.map {
            OpenRouterChatMessagePayload(role: $0.role.rawValue, content: agentSystemPromptIfNeeded(for: $0))
        }
        let needsLocalTools = Self.needsLocalTools(messages)
        var retriedMissingTools = false

        for _ in 0..<maxToolRounds {
            let result = try await client.completeChatWithTools(
                apiKey: apiKey,
                model: model,
                messages: payloadMessages,
                tools: Self.toolDefinitions
            )

            if result.toolCalls.isEmpty {
                if needsLocalTools && !retriedMissingTools {
                    retriedMissingTools = true
                    payloadMessages.append(OpenRouterChatMessagePayload(role: "assistant", content: result.content))
                    payloadMessages.append(
                        OpenRouterChatMessagePayload(
                            role: "user",
                            content: "You answered with advice instead of acting. Execute the request now using the local tools. If a permission blocks you, report the specific permission or path."
                        )
                    )
                    continue
                }

                return result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Done."
                    : result.content
            }

            payloadMessages.append(
                OpenRouterChatMessagePayload(
                    role: "assistant",
                    content: result.content.isEmpty ? nil : result.content,
                    toolCalls: result.toolCalls
                )
            )

            for toolCall in result.toolCalls {
                let preview = Self.preview(for: toolCall)
                await onToolEvent("Requested \(preview.title)")
                if preview.requiresConfirmation {
                    guard await confirmTool(preview) else {
                        await onToolEvent("Skipped \(preview.title)")
                        payloadMessages.append(
                            OpenRouterChatMessagePayload(
                                role: "tool",
                                content: "The user declined this local action. Do not attempt it again unless the user asks.",
                                toolCallID: toolCall.id
                            )
                        )
                        continue
                    }
                }

                await onToolEvent("Running \(preview.title)")
                let output = await execute(toolCall)
                payloadMessages.append(
                    OpenRouterChatMessagePayload(
                        role: "tool",
                        content: output,
                        toolCallID: toolCall.id
                    )
                )
            }
        }

        return "Agent stopped after reaching the local tool limit. Ask me to continue if you want another pass."
    }

    private func agentSystemPromptIfNeeded(for message: ChatMessage) -> String {
        guard message.role == .system else {
            return message.content
        }

        return """
        \(message.content)

        Local Agent Mode is enabled. You are an acting desktop and coding agent, not an advice bot. When the user asks you to create, edit, organize, inspect, move, rename, run, install, build, test, open, or otherwise change something on this Mac, use tools to do it. Do not answer with generic instructions for tasks you can perform. Prefer the smallest effective action. Use absolute paths when possible. The user has requested broad local access, but macOS privacy permissions may still block protected locations until granted in System Settings. Destructive operations require user confirmation. After using tools, explain what you changed or found concisely.
        """
    }

    private func execute(_ toolCall: OpenRouterToolCall) async -> String {
        do {
            let arguments = try Self.decodeArguments(toolCall.function.arguments)
            let result: String

            switch toolCall.function.name {
            case "list_directory":
                result = try listDirectory(arguments)
            case "read_text_file":
                result = try readTextFile(arguments)
            case "write_text_file":
                result = try writeTextFile(arguments)
            case "create_directory":
                result = try createDirectory(arguments)
            case "move_item":
                result = try moveItem(arguments)
            case "copy_item":
                result = try copyItem(arguments)
            case "trash_item":
                result = try trashItem(arguments)
            case "run_shell_command":
                result = try await runShellCommand(arguments)
            case "open_item":
                result = try openItem(arguments)
            default:
                throw AgentServiceError.unknownTool(toolCall.function.name)
            }

            return Self.truncated(result, maxCharacters: maxToolOutputCharacters)
        } catch {
            return "Tool error: \(error.localizedDescription)"
        }
    }

    private func listDirectory(_ arguments: [String: Any]) throws -> String {
        let path = try Self.stringValue("path", in: arguments)
        let url = URL(fileURLWithPath: Self.expandedPath(path))
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let rows = try contents.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { item -> String in
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let marker = values.isDirectory == true ? "/" : ""
                let size = values.fileSize.map { " \($0) bytes" } ?? ""
                return "\(item.lastPathComponent)\(marker)\(size)"
            }

        return rows.isEmpty ? "Directory is empty." : rows.joined(separator: "\n")
    }

    private func readTextFile(_ arguments: [String: Any]) throws -> String {
        let path = try Self.stringValue("path", in: arguments)
        let maxBytes = min(max(Self.intValue("max_bytes", in: arguments) ?? 120_000, 1), 1_000_000)
        let url = URL(fileURLWithPath: Self.expandedPath(path))

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentServiceError.missingPath
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let data = try handle.read(upToCount: maxBytes) ?? Data()
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }

        return "The file was read, but it does not look like text."
    }

    private func writeTextFile(_ arguments: [String: Any]) throws -> String {
        let path = try Self.stringValue("path", in: arguments)
        let content = try Self.stringValue("content", in: arguments)
        let url = URL(fileURLWithPath: Self.expandedPath(path))
        let directory = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)

        return "Wrote \(content.utf8.count) bytes to \(url.path)."
    }

    private func createDirectory(_ arguments: [String: Any]) throws -> String {
        let path = try Self.stringValue("path", in: arguments)
        let url = URL(fileURLWithPath: Self.expandedPath(path))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "Created directory \(url.path)."
    }

    private func moveItem(_ arguments: [String: Any]) throws -> String {
        let source = URL(fileURLWithPath: Self.expandedPath(try Self.stringValue("source_path", in: arguments)))
        let destination = URL(fileURLWithPath: Self.expandedPath(try Self.stringValue("destination_path", in: arguments)))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
        return "Moved \(source.path) to \(destination.path)."
    }

    private func copyItem(_ arguments: [String: Any]) throws -> String {
        let source = URL(fileURLWithPath: Self.expandedPath(try Self.stringValue("source_path", in: arguments)))
        let destination = URL(fileURLWithPath: Self.expandedPath(try Self.stringValue("destination_path", in: arguments)))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return "Copied \(source.path) to \(destination.path)."
    }

    private func trashItem(_ arguments: [String: Any]) throws -> String {
        let path = URL(fileURLWithPath: Self.expandedPath(try Self.stringValue("path", in: arguments)))
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: path, resultingItemURL: &resultingURL)
        return "Moved \(path.path) to the Trash."
    }

    private func runShellCommand(_ arguments: [String: Any]) async throws -> String {
        let command = try Self.stringValue("command", in: arguments)
        guard !Self.isBlockedShellCommand(command) else {
            throw AgentServiceError.blockedShellCommand
        }
        let workingDirectory = (try? Self.stringValue("working_directory", in: arguments)).map(Self.expandedPath)
        let timeout = min(max(Self.intValue("timeout_seconds", in: arguments) ?? 30, 1), 120)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let started = Date()
        while process.isRunning {
            if Date().timeIntervalSince(started) > TimeInterval(timeout) {
                process.terminate()
                throw AgentServiceError.commandTimedOut
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return """
        exit_code: \(process.terminationStatus)
        stdout:
        \(stdout)
        stderr:
        \(stderr)
        """
    }

    private func openItem(_ arguments: [String: Any]) throws -> String {
        let target = try Self.stringValue("path_or_url", in: arguments)

        let url: URL
        if let parsedURL = URL(string: target), parsedURL.scheme != nil {
            url = parsedURL
        } else {
            url = URL(fileURLWithPath: Self.expandedPath(target))
        }

        NSWorkspace.shared.open(url)
        return "Opened \(target)."
    }

    private static func decodeArguments(_ arguments: String) throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8) else {
            throw AgentServiceError.invalidToolArguments("Arguments were not UTF-8.")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw AgentServiceError.invalidToolArguments("Expected a JSON object.")
        }

        return dictionary
    }

    private static func stringValue(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentServiceError.invalidToolArguments("Missing `\(key)`.")
        }

        return value
    }

    private static func intValue(_ key: String, in arguments: [String: Any]) -> Int? {
        if let value = arguments[key] as? Int {
            return value
        }
        if let value = arguments[key] as? Double {
            return Int(value)
        }
        if let value = arguments[key] as? String {
            return Int(value)
        }
        return nil
    }

    private static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }

        return String(text.prefix(maxCharacters)) + "\n... output truncated ..."
    }

    static func preview(for toolCall: OpenRouterToolCall) -> AgentToolPreview {
        let arguments = (try? decodeArguments(toolCall.function.arguments)) ?? [:]
        let name = toolCall.function.name

        switch name {
        case "list_directory":
            let path = (try? stringValue("path", in: arguments)).map(expandedPath) ?? "unknown path"
            return AgentToolPreview(toolName: name, title: "List Directory", detail: path, requiresConfirmation: false)
        case "read_text_file":
            let path = (try? stringValue("path", in: arguments)).map(expandedPath) ?? "unknown path"
            return AgentToolPreview(toolName: name, title: "Read Text File", detail: path, requiresConfirmation: false)
        case "write_text_file":
            let path = (try? stringValue("path", in: arguments)).map(expandedPath) ?? "unknown path"
            let byteCount = ((try? stringValue("content", in: arguments)) ?? "").utf8.count
            return AgentToolPreview(toolName: name, title: "Write Text File", detail: "\(path)\n\(byteCount) bytes", requiresConfirmation: true)
        case "create_directory":
            let path = (try? stringValue("path", in: arguments)).map(expandedPath) ?? "unknown path"
            return AgentToolPreview(toolName: name, title: "Create Directory", detail: path, requiresConfirmation: true)
        case "move_item":
            let source = (try? stringValue("source_path", in: arguments)).map(expandedPath) ?? "unknown source"
            let destination = (try? stringValue("destination_path", in: arguments)).map(expandedPath) ?? "unknown destination"
            return AgentToolPreview(toolName: name, title: "Move Item", detail: "\(source)\n-> \(destination)", requiresConfirmation: true)
        case "copy_item":
            let source = (try? stringValue("source_path", in: arguments)).map(expandedPath) ?? "unknown source"
            let destination = (try? stringValue("destination_path", in: arguments)).map(expandedPath) ?? "unknown destination"
            return AgentToolPreview(toolName: name, title: "Copy Item", detail: "\(source)\n-> \(destination)", requiresConfirmation: true)
        case "trash_item":
            let path = (try? stringValue("path", in: arguments)).map(expandedPath) ?? "unknown path"
            return AgentToolPreview(toolName: name, title: "Move to Trash", detail: path, requiresConfirmation: true)
        case "run_shell_command":
            let command = (try? stringValue("command", in: arguments)) ?? "unknown command"
            let directory = (try? stringValue("working_directory", in: arguments)).map(expandedPath)
            let detail = directory.map { "cd \($0)\n\(command)" } ?? command
            return AgentToolPreview(toolName: name, title: "Run Shell Command", detail: detail, requiresConfirmation: true)
        case "open_item":
            let target = (try? stringValue("path_or_url", in: arguments)) ?? "unknown target"
            return AgentToolPreview(toolName: name, title: "Open Item", detail: target, requiresConfirmation: true)
        default:
            return AgentToolPreview(toolName: name, title: name, detail: toolCall.function.arguments, requiresConfirmation: true)
        }
    }

    static func isBlockedShellCommand(_ command: String) -> Bool {
        let normalized = command
            .lowercased()
            .replacingOccurrences(of: #"\\\s*\n"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blockedPatterns = [
            #"rm\s+-[^\n;|&]*r[^\n;|&]*f[^\n;|&]*(/|~|\$home)(\s|$)"#,
            #"rm\s+-[^\n;|&]*f[^\n;|&]*r[^\n;|&]*(/|~|\$home)(\s|$)"#,
            #"diskutil\s+(erase|partition|apfs\s+delete)"#,
            #"mkfs(\.|\s)"#,
            #"dd\s+if=.*\s+of=/dev/"#,
            #":\s*\(\)\s*\{\s*:\s*\|\s*:"#,
            #"chmod\s+-r\s+777\s+/"#,
            #"chown\s+-r\s+.*\s+/"#
        ]

        return blockedPatterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func needsLocalTools(_ messages: [ChatMessage]) -> Bool {
        guard let latestUserMessage = messages.last(where: { $0.role == .user })?.content.lowercased() else {
            return false
        }

        let actionWords = [
            "create", "make", "write", "edit", "modify", "organize", "organise",
            "move", "rename", "delete", "trash", "copy", "read", "list",
            "open", "run", "execute", "install", "build", "test", "fix"
        ]

        let localTargets = [
            "file", "folder", "directory", "downloads", "desktop", "documents",
            "project", "app", "code", "terminal", "command", "script"
        ]

        return actionWords.contains { latestUserMessage.contains($0) }
            && localTargets.contains { latestUserMessage.contains($0) }
    }

    static let toolDefinitions: [OpenRouterTool] = [
        OpenRouterTool(
            function: .init(
                name: "list_directory",
                description: "List files and folders at a local filesystem path.",
                parameters: .init(
                    properties: [
                        "path": .init(type: "string", description: "Absolute path or tilde path to list.")
                    ],
                    required: ["path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "read_text_file",
                description: "Read a local text file. Use max_bytes to avoid huge outputs.",
                parameters: .init(
                    properties: [
                        "path": .init(type: "string", description: "Absolute path or tilde path to read."),
                        "max_bytes": .init(type: "integer", description: "Optional byte limit. Defaults to 120000.")
                    ],
                    required: ["path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "write_text_file",
                description: "Create or overwrite a local UTF-8 text file.",
                parameters: .init(
                    properties: [
                        "path": .init(type: "string", description: "Absolute path or tilde path to write."),
                        "content": .init(type: "string", description: "Complete UTF-8 text content to write.")
                    ],
                    required: ["path", "content"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "create_directory",
                description: "Create a local directory, including intermediate directories.",
                parameters: .init(
                    properties: [
                        "path": .init(type: "string", description: "Absolute path or tilde path to create.")
                    ],
                    required: ["path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "move_item",
                description: "Move or rename a local file or folder.",
                parameters: .init(
                    properties: [
                        "source_path": .init(type: "string", description: "Absolute path or tilde path to move."),
                        "destination_path": .init(type: "string", description: "Absolute destination path or tilde path.")
                    ],
                    required: ["source_path", "destination_path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "copy_item",
                description: "Copy a local file or folder.",
                parameters: .init(
                    properties: [
                        "source_path": .init(type: "string", description: "Absolute path or tilde path to copy."),
                        "destination_path": .init(type: "string", description: "Absolute destination path or tilde path.")
                    ],
                    required: ["source_path", "destination_path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "trash_item",
                description: "Move a local file or folder to the macOS Trash.",
                parameters: .init(
                    properties: [
                        "path": .init(type: "string", description: "Absolute path or tilde path to move to Trash.")
                    ],
                    required: ["path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "run_shell_command",
                description: "Run a zsh shell command on this Mac and return stdout, stderr, and exit code.",
                parameters: .init(
                    properties: [
                        "command": .init(type: "string", description: "The zsh command to run."),
                        "working_directory": .init(type: "string", description: "Optional working directory path."),
                        "timeout_seconds": .init(type: "integer", description: "Optional timeout from 1 to 120 seconds. Defaults to 30.")
                    ],
                    required: ["command"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "open_item",
                description: "Open a local file, folder, app path, or URL with macOS.",
                parameters: .init(
                    properties: [
                        "path_or_url": .init(type: "string", description: "A local path, app path, folder path, or URL.")
                    ],
                    required: ["path_or_url"]
                )
            )
        )
    ]
}
