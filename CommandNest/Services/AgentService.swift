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

        Local Agent Mode is enabled. You are an acting desktop, coding, browser, email, GitHub, and MCP agent, not an advice bot. When the user asks you to create, edit, organize, inspect, move, rename, run, install, build, test, browse, send email, commit, push, create a pull request, create a release, call an MCP server, or otherwise change something on this Mac, use tools to do it. Do not answer with generic instructions for tasks you can perform. Prefer the smallest effective action. Use absolute paths when possible. Read repository state before editing code, run relevant tests after changes, and summarize exact files or commands used. The user has requested broad local access, but macOS privacy permissions may still block protected locations until granted in System Settings. Sending email, browser control, GitHub uploads, shell commands, writes, and external MCP calls require user confirmation. After using tools, explain what you changed or found concisely.
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
            case "search_files":
                result = try searchFiles(arguments)
            case "grep_text":
                result = try await grepText(arguments)
            case "replace_in_text_file":
                result = try replaceInTextFile(arguments)
            case "run_project_tests":
                result = try await runProjectTests(arguments)
            case "git_status":
                result = try await gitStatus(arguments)
            case "git_diff":
                result = try await gitDiff(arguments)
            case "git_commit":
                result = try await gitCommit(arguments)
            case "git_push":
                result = try await gitPush(arguments)
            case "github_create_pull_request":
                result = try await githubCreatePullRequest(arguments)
            case "github_create_release":
                result = try await githubCreateRelease(arguments)
            case "browser_navigate":
                result = try await browserNavigate(arguments)
            case "browser_get_page_text":
                result = try await browserGetPageText(arguments)
            case "browser_execute_javascript":
                result = try await browserExecuteJavaScript(arguments)
            case "search_web":
                result = try searchWeb(arguments)
            case "compose_email":
                result = try composeEmail(arguments)
            case "send_email":
                result = try await sendEmail(arguments)
            case "mcp_list_servers":
                result = Self.mcpListServers()
            case "mcp_list_tools":
                result = try await mcpListTools(arguments)
            case "mcp_call_tool":
                result = try await mcpCallTool(arguments)
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
        let timeout = min(max(Self.intValue("timeout_seconds", in: arguments) ?? 30, 1), 600)

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

    private func runAppleScript(_ script: String) async throws -> String {
        try await runShellCommand([
            "command": "osascript -e \(Self.shellQuoted(script))",
            "timeout_seconds": 60
        ])
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

    private func searchFiles(_ arguments: [String: Any]) throws -> String {
        let rootPath = try Self.stringValue("root_path", in: arguments)
        let query = try Self.stringValue("query", in: arguments).lowercased()
        let maxResults = min(max(Self.intValue("max_results", in: arguments) ?? 100, 1), 500)
        let rootURL = URL(fileURLWithPath: Self.expandedPath(rootPath))

        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw AgentServiceError.missingPath
        }

        let skippedDirectories = Set([".git", "node_modules", "DerivedData", "build", "dist", ".build"])
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var matches: [String] = []
        while let item = enumerator?.nextObject() as? URL {
            let name = item.lastPathComponent
            if skippedDirectories.contains(name) {
                enumerator?.skipDescendants()
                continue
            }

            if name.lowercased().contains(query) || item.path.lowercased().contains(query) {
                matches.append(item.path)
                if matches.count >= maxResults {
                    break
                }
            }
        }

        return matches.isEmpty ? "No matching files found." : matches.joined(separator: "\n")
    }

    private func grepText(_ arguments: [String: Any]) async throws -> String {
        let rootPath = Self.expandedPath(try Self.stringValue("root_path", in: arguments))
        let pattern = try Self.stringValue("pattern", in: arguments)
        let maxResults = min(max(Self.intValue("max_results", in: arguments) ?? 100, 1), 500)
        let command = """
        if command -v rg >/dev/null 2>&1; then
          rg -n --hidden --glob '!.git/**' --glob '!node_modules/**' --glob '!dist/**' --glob '!build/**' --glob '!DerivedData/**' --max-count \(maxResults) \(Self.shellQuoted(pattern)) \(Self.shellQuoted(rootPath))
        else
          grep -RIn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=DerivedData \(Self.shellQuoted(pattern)) \(Self.shellQuoted(rootPath)) | head -n \(maxResults)
        fi
        """

        return try await runShellCommand([
            "command": command,
            "working_directory": rootPath,
            "timeout_seconds": Self.intValue("timeout_seconds", in: arguments) ?? 30
        ])
    }

    private func replaceInTextFile(_ arguments: [String: Any]) throws -> String {
        let path = try Self.stringValue("path", in: arguments)
        let find = try Self.stringValue("find", in: arguments)
        let replacement = try Self.stringValue("replacement", in: arguments)
        let replaceAll = Self.boolValue("replace_all", in: arguments) ?? false
        let url = URL(fileURLWithPath: Self.expandedPath(path))

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentServiceError.missingPath
        }

        let original = try String(contentsOf: url, encoding: .utf8)
        guard original.contains(find) else {
            return "No matching text found in \(url.path)."
        }

        let updated: String
        let replacementCount: Int
        if replaceAll {
            replacementCount = original.components(separatedBy: find).count - 1
            updated = original.replacingOccurrences(of: find, with: replacement)
        } else if let range = original.range(of: find) {
            replacementCount = 1
            updated = original.replacingCharacters(in: range, with: replacement)
        } else {
            replacementCount = 0
            updated = original
        }

        try updated.write(to: url, atomically: true, encoding: .utf8)
        return "Replaced \(replacementCount) occurrence\(replacementCount == 1 ? "" : "s") in \(url.path)."
    }

    private func runProjectTests(_ arguments: [String: Any]) async throws -> String {
        let projectPath = Self.expandedPath(try Self.stringValue("project_path", in: arguments))
        let timeout = min(max(Self.intValue("timeout_seconds", in: arguments) ?? 120, 1), 600)
        let command = try Self.optionalStringValue("command", in: arguments) ?? inferTestCommand(projectPath: projectPath)

        return try await runShellCommand([
            "command": command,
            "working_directory": projectPath,
            "timeout_seconds": timeout
        ])
    }

    private func inferTestCommand(projectPath: String) throws -> String {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: projectPath)

        if fileManager.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return "swift test"
        }

        if fileManager.fileExists(atPath: root.appendingPathComponent("package.json").path) {
            return "npm test"
        }

        if fileManager.fileExists(atPath: root.appendingPathComponent("pyproject.toml").path)
            || fileManager.fileExists(atPath: root.appendingPathComponent("pytest.ini").path) {
            return "python3 -m pytest"
        }

        let projects = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))
            ?? []
        if let xcodeProject = projects.first(where: { $0.pathExtension == "xcodeproj" }) {
            let scheme = xcodeProject.deletingPathExtension().lastPathComponent
            return "xcodebuild -project \(Self.shellQuoted(xcodeProject.lastPathComponent)) -scheme \(Self.shellQuoted(scheme)) -destination 'platform=macOS' test"
        }

        throw AgentServiceError.invalidToolArguments("No test command was provided and no known project test runner was detected.")
    }

    private func gitStatus(_ arguments: [String: Any]) async throws -> String {
        let repo = Self.expandedPath(try Self.stringValue("repository_path", in: arguments))
        return try await runShellCommand([
            "command": "git -C \(Self.shellQuoted(repo)) status --short --branch",
            "working_directory": repo,
            "timeout_seconds": 30
        ])
    }

    private func gitDiff(_ arguments: [String: Any]) async throws -> String {
        let repo = Self.expandedPath(try Self.stringValue("repository_path", in: arguments))
        let pathspec = try Self.optionalStringValue("pathspec", in: arguments)
        let limit = min(max(Self.intValue("max_bytes", in: arguments) ?? 80_000, 1), 300_000)
        let diffCommand = pathspec.map {
            "git -C \(Self.shellQuoted(repo)) diff -- \(Self.shellQuoted($0))"
        } ?? "git -C \(Self.shellQuoted(repo)) diff"

        let output = try await runShellCommand([
            "command": "git -C \(Self.shellQuoted(repo)) diff --stat && \(diffCommand)",
            "working_directory": repo,
            "timeout_seconds": 30
        ])
        return Self.truncated(output, maxCharacters: limit)
    }

    private func gitCommit(_ arguments: [String: Any]) async throws -> String {
        let repo = Self.expandedPath(try Self.stringValue("repository_path", in: arguments))
        let message = try Self.stringValue("message", in: arguments)
        let paths = Self.listValue("paths", in: arguments)
        let addCommand: String
        if paths.isEmpty {
            addCommand = "git -C \(Self.shellQuoted(repo)) add -A"
        } else {
            addCommand = "git -C \(Self.shellQuoted(repo)) add -- \(paths.map(Self.shellQuoted).joined(separator: " "))"
        }

        return try await runShellCommand([
            "command": "\(addCommand) && git -C \(Self.shellQuoted(repo)) commit -m \(Self.shellQuoted(message))",
            "working_directory": repo,
            "timeout_seconds": 60
        ])
    }

    private func gitPush(_ arguments: [String: Any]) async throws -> String {
        let repo = Self.expandedPath(try Self.stringValue("repository_path", in: arguments))
        let remote = try Self.optionalStringValue("remote", in: arguments) ?? "origin"
        let branch = try Self.optionalStringValue("branch", in: arguments)
        let branchPart = branch.map { " \(Self.shellQuoted($0))" } ?? ""

        return try await runShellCommand([
            "command": "git -C \(Self.shellQuoted(repo)) push \(Self.shellQuoted(remote))\(branchPart)",
            "working_directory": repo,
            "timeout_seconds": 120
        ])
    }

    private func githubCreatePullRequest(_ arguments: [String: Any]) async throws -> String {
        let repo = Self.expandedPath(try Self.stringValue("repository_path", in: arguments))
        let title = try Self.stringValue("title", in: arguments)
        let body = try Self.optionalStringValue("body", in: arguments) ?? ""
        let base = try Self.optionalStringValue("base", in: arguments)
        let head = try Self.optionalStringValue("head", in: arguments)
        let draft = Self.boolValue("draft", in: arguments) ?? true
        var command = "gh pr create --title \(Self.shellQuoted(title)) --body \(Self.shellQuoted(body))"
        if let base {
            command += " --base \(Self.shellQuoted(base))"
        }
        if let head {
            command += " --head \(Self.shellQuoted(head))"
        }
        if draft {
            command += " --draft"
        }

        return try await runShellCommand([
            "command": command,
            "working_directory": repo,
            "timeout_seconds": 120
        ])
    }

    private func githubCreateRelease(_ arguments: [String: Any]) async throws -> String {
        let repo = Self.expandedPath(try Self.stringValue("repository_path", in: arguments))
        let tag = try Self.stringValue("tag", in: arguments)
        let title = try Self.optionalStringValue("title", in: arguments)
        let notes = try Self.optionalStringValue("notes", in: arguments)
        let assets = Self.listValue("asset_paths", in: arguments).map { Self.expandedPath($0) }
        var command = "gh release create \(Self.shellQuoted(tag))"
        if !assets.isEmpty {
            command += " \(assets.map(Self.shellQuoted).joined(separator: " "))"
        }
        if let title {
            command += " --title \(Self.shellQuoted(title))"
        }
        if let notes {
            command += " --notes \(Self.shellQuoted(notes))"
        }

        return try await runShellCommand([
            "command": command,
            "working_directory": repo,
            "timeout_seconds": 180
        ])
    }

    private func browserNavigate(_ arguments: [String: Any]) async throws -> String {
        let urlString = try Self.stringValue("url", in: arguments)
        let browser = (try Self.optionalStringValue("browser", in: arguments) ?? "default").lowercased()

        guard let url = URL(string: urlString), url.scheme != nil else {
            throw AgentServiceError.invalidToolArguments("Expected a full URL including scheme.")
        }

        if browser.contains("safari") {
            _ = try await runAppleScript("""
            tell application "Safari"
              if (count of documents) = 0 then
                make new document with properties {URL:\(Self.appleScriptString(urlString))}
              else
                set URL of front document to \(Self.appleScriptString(urlString))
              end if
              activate
            end tell
            """)
        } else if browser.contains("chrome") {
            _ = try await runAppleScript("""
            tell application "Google Chrome"
              if (count of windows) = 0 then make new window
              set URL of active tab of front window to \(Self.appleScriptString(urlString))
              activate
            end tell
            """)
        } else {
            NSWorkspace.shared.open(url)
        }

        return "Navigated \(browser) to \(urlString)."
    }

    private func browserGetPageText(_ arguments: [String: Any]) async throws -> String {
        let browser = try Self.optionalStringValue("browser", in: arguments) ?? "Safari"
        let maxCharacters = min(max(Self.intValue("max_characters", in: arguments) ?? 20_000, 1), 120_000)
        let javascript = "document.body ? document.body.innerText.slice(0, \(maxCharacters)) : ''"
        let output = try await runBrowserJavaScript(browser: browser, javascript: javascript)
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No page text returned." : output
    }

    private func browserExecuteJavaScript(_ arguments: [String: Any]) async throws -> String {
        let browser = try Self.optionalStringValue("browser", in: arguments) ?? "Safari"
        let javascript = try Self.stringValue("javascript", in: arguments)
        return try await runBrowserJavaScript(browser: browser, javascript: javascript)
    }

    private func runBrowserJavaScript(browser: String, javascript: String) async throws -> String {
        let normalizedBrowser = browser.lowercased()
        if normalizedBrowser.contains("chrome") {
            return try await runAppleScript("""
            tell application "Google Chrome"
              if (count of windows) = 0 then error "Google Chrome has no open windows."
              execute active tab of front window javascript \(Self.appleScriptString(javascript))
            end tell
            """)
        }

        return try await runAppleScript("""
        tell application "Safari"
          if (count of documents) = 0 then error "Safari has no open documents."
          do JavaScript \(Self.appleScriptString(javascript)) in front document
        end tell
        """)
    }

    private func searchWeb(_ arguments: [String: Any]) throws -> String {
        let query = try Self.stringValue("query", in: arguments)
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else {
            throw AgentServiceError.invalidToolArguments("Could not build search URL.")
        }

        NSWorkspace.shared.open(url)
        return "Opened web search for \(query)."
    }

    private func composeEmail(_ arguments: [String: Any]) throws -> String {
        let to = Self.listValue("to", in: arguments).joined(separator: ",")
        let subject = try Self.optionalStringValue("subject", in: arguments) ?? ""
        let body = try Self.optionalStringValue("body", in: arguments) ?? ""
        let cc = Self.listValue("cc", in: arguments).joined(separator: ",")
        let bcc = Self.listValue("bcc", in: arguments).joined(separator: ",")

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            subject.isEmpty ? nil : URLQueryItem(name: "subject", value: subject),
            body.isEmpty ? nil : URLQueryItem(name: "body", value: body),
            cc.isEmpty ? nil : URLQueryItem(name: "cc", value: cc),
            bcc.isEmpty ? nil : URLQueryItem(name: "bcc", value: bcc)
        ].compactMap { $0 }

        guard let url = components.url else {
            throw AgentServiceError.invalidToolArguments("Could not build mail draft URL.")
        }

        NSWorkspace.shared.open(url)
        return "Opened an email draft\(to.isEmpty ? "" : " to \(to)")."
    }

    private func sendEmail(_ arguments: [String: Any]) async throws -> String {
        let recipients = Self.listValue("to", in: arguments)
        guard !recipients.isEmpty else {
            throw AgentServiceError.invalidToolArguments("Missing `to` recipient.")
        }

        let subject = try Self.optionalStringValue("subject", in: arguments) ?? ""
        let body = try Self.optionalStringValue("body", in: arguments) ?? ""
        let cc = Self.listValue("cc", in: arguments)
        let bcc = Self.listValue("bcc", in: arguments)
        let attachments = Self.listValue("attachment_paths", in: arguments).map(Self.expandedPath)

        let recipientLines = recipients.map {
            "make new to recipient at end of to recipients with properties {address:\(Self.appleScriptString($0))}"
        }.joined(separator: "\n")
        let ccLines = cc.map {
            "make new cc recipient at end of cc recipients with properties {address:\(Self.appleScriptString($0))}"
        }.joined(separator: "\n")
        let bccLines = bcc.map {
            "make new bcc recipient at end of bcc recipients with properties {address:\(Self.appleScriptString($0))}"
        }.joined(separator: "\n")
        let attachmentLines = attachments.map {
            "make new attachment with properties {file name:(POSIX file \(Self.appleScriptString($0)))} at after last paragraph"
        }.joined(separator: "\n")

        _ = try await runAppleScript("""
        tell application "Mail"
          set newMessage to make new outgoing message with properties {subject:\(Self.appleScriptString(subject)), content:\(Self.appleScriptString(body)), visible:false}
          tell newMessage
            \(recipientLines)
            \(ccLines)
            \(bccLines)
            \(attachmentLines)
            send
          end tell
        end tell
        """)

        return "Sent email to \(recipients.joined(separator: ", "))."
    }

    private static func mcpListServers() -> String {
        let servers = mcpServerConfigs()
        guard !servers.isEmpty else {
            return "No MCP servers are configured."
        }

        return servers.map { server in
            let args = server.args.map(shellQuoted).joined(separator: " ")
            let envKeys = server.env.keys.sorted()
            let envSummary = envKeys.isEmpty ? "inherits environment" : "env: \(envKeys.joined(separator: ", "))"
            return "\(server.id): \(server.name)\n  command: \(server.command) \(args)\n  \(envSummary)"
        }.joined(separator: "\n\n")
    }

    private func mcpListTools(_ arguments: [String: Any]) async throws -> String {
        let serverID = try Self.stringValue("server_id", in: arguments)
        let server = try Self.mcpServerConfig(id: serverID)
        let timeout = min(max(Self.intValue("timeout_seconds", in: arguments) ?? 45, 1), 180)
        let client = MCPStdioClient(config: server, timeout: TimeInterval(timeout))
        let tools = try await client.listTools()

        guard !tools.isEmpty else {
            return "MCP server \(serverID) returned no tools."
        }

        return tools.map { tool in
            let description = tool.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return description.isEmpty ? "- \(tool.name)" : "- \(tool.name): \(description)"
        }.joined(separator: "\n")
    }

    private func mcpCallTool(_ arguments: [String: Any]) async throws -> String {
        let serverID = try Self.stringValue("server_id", in: arguments)
        let toolName = try Self.stringValue("tool_name", in: arguments)
        let toolArguments = try Self.dictionaryValue("arguments", in: arguments)
        let timeout = min(max(Self.intValue("timeout_seconds", in: arguments) ?? 90, 1), 300)
        let server = try Self.mcpServerConfig(id: serverID)
        let client = MCPStdioClient(config: server, timeout: TimeInterval(timeout))
        return try await client.callTool(name: toolName, arguments: toolArguments)
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

    private static func optionalStringValue(_ key: String, in arguments: [String: Any]) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }
        guard let string = value as? String else {
            throw AgentServiceError.invalidToolArguments("`\(key)` must be a string.")
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(_ key: String, in arguments: [String: Any]) -> Bool? {
        if let value = arguments[key] as? Bool {
            return value
        }
        if let value = arguments[key] as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func listValue(_ key: String, in arguments: [String: Any]) -> [String] {
        if let values = arguments[key] as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let values = arguments[key] as? [Any] {
            return values.compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let value = arguments[key] as? String {
            return value
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func dictionaryValue(_ key: String, in arguments: [String: Any]) throws -> [String: Any] {
        if let dictionary = arguments[key] as? [String: Any] {
            return dictionary
        }
        if let jsonString = arguments[key] as? String {
            let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return [:]
            }
            return try decodeArguments(trimmed)
        }
        if arguments[key] == nil {
            return [:]
        }
        throw AgentServiceError.invalidToolArguments("`\(key)` must be an object or JSON object string.")
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

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }

        return String(text.prefix(maxCharacters)) + "\n... output truncated ..."
    }

    private static func mcpServerConfig(id: String) throws -> MCPServerConfig {
        guard let server = mcpServerConfigs().first(where: { $0.id == id }) else {
            throw AgentServiceError.invalidToolArguments("Unknown MCP server `\(id)`. Call mcp_list_servers first.")
        }
        return server
    }

    private static func mcpServerConfigs() -> [MCPServerConfig] {
        var servers = builtInMCPServerConfigs()
        for server in configuredMCPServers() {
            servers.removeAll { $0.id == server.id }
            servers.append(server)
        }
        return servers.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private static func builtInMCPServerConfigs() -> [MCPServerConfig] {
        [
            MCPServerConfig(
                id: "filesystem",
                name: "Filesystem MCP",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", NSHomeDirectory()],
                env: [:]
            ),
            MCPServerConfig(
                id: "github",
                name: "GitHub MCP",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                env: [:]
            ),
            MCPServerConfig(
                id: "browser",
                name: "Playwright Browser MCP",
                command: "npx",
                args: ["-y", "@playwright/mcp@latest"],
                env: [:]
            )
        ]
    }

    private static func configuredMCPServers() -> [MCPServerConfig] {
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".commandnest/mcp.json"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/CommandNest/mcp.json")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(MCPConfigFile.self, from: data)
                return config.mcpServers.map { id, server in
                    MCPServerConfig(
                        id: id,
                        name: server.name ?? id,
                        command: server.command,
                        args: server.args ?? [],
                        env: server.env ?? [:]
                    )
                }
            } catch {
                return []
            }
        }

        return []
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
        case "search_files":
            let root = (try? stringValue("root_path", in: arguments)).map(expandedPath) ?? "unknown root"
            let query = (try? stringValue("query", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Search Files", detail: "\(root)\nquery: \(query)", requiresConfirmation: false)
        case "grep_text":
            let root = (try? stringValue("root_path", in: arguments)).map(expandedPath) ?? "unknown root"
            let pattern = (try? stringValue("pattern", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Search Text", detail: "\(root)\npattern: \(pattern)", requiresConfirmation: false)
        case "replace_in_text_file":
            let path = (try? stringValue("path", in: arguments)).map(expandedPath) ?? "unknown path"
            return AgentToolPreview(toolName: name, title: "Edit Text File", detail: path, requiresConfirmation: true)
        case "run_project_tests":
            let project = (try? stringValue("project_path", in: arguments)).map(expandedPath) ?? "unknown project"
            let command = try? optionalStringValue("command", in: arguments)
            return AgentToolPreview(toolName: name, title: "Run Project Tests", detail: command.map { "\(project)\n\($0)" } ?? project, requiresConfirmation: true)
        case "git_status":
            let repo = (try? stringValue("repository_path", in: arguments)).map(expandedPath) ?? "unknown repository"
            return AgentToolPreview(toolName: name, title: "Git Status", detail: repo, requiresConfirmation: false)
        case "git_diff":
            let repo = (try? stringValue("repository_path", in: arguments)).map(expandedPath) ?? "unknown repository"
            return AgentToolPreview(toolName: name, title: "Git Diff", detail: repo, requiresConfirmation: false)
        case "git_commit":
            let repo = (try? stringValue("repository_path", in: arguments)).map(expandedPath) ?? "unknown repository"
            let message = (try? stringValue("message", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Git Commit", detail: "\(repo)\n\(message)", requiresConfirmation: true)
        case "git_push":
            let repo = (try? stringValue("repository_path", in: arguments)).map(expandedPath) ?? "unknown repository"
            return AgentToolPreview(toolName: name, title: "Git Push", detail: repo, requiresConfirmation: true)
        case "github_create_pull_request":
            let title = (try? stringValue("title", in: arguments)) ?? "Untitled PR"
            return AgentToolPreview(toolName: name, title: "Create GitHub Pull Request", detail: title, requiresConfirmation: true)
        case "github_create_release":
            let tag = (try? stringValue("tag", in: arguments)) ?? "unknown tag"
            return AgentToolPreview(toolName: name, title: "Create GitHub Release", detail: tag, requiresConfirmation: true)
        case "browser_navigate":
            let url = (try? stringValue("url", in: arguments)) ?? "unknown URL"
            return AgentToolPreview(toolName: name, title: "Navigate Browser", detail: url, requiresConfirmation: true)
        case "browser_get_page_text":
            let browser = (try? optionalStringValue("browser", in: arguments)) ?? "Safari"
            return AgentToolPreview(toolName: name, title: "Read Browser Page", detail: browser, requiresConfirmation: true)
        case "browser_execute_javascript":
            let browser = (try? optionalStringValue("browser", in: arguments)) ?? "Safari"
            let javascript = (try? stringValue("javascript", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Control Browser", detail: "\(browser)\n\(javascript)", requiresConfirmation: true)
        case "search_web":
            let query = (try? stringValue("query", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Search Web", detail: query, requiresConfirmation: true)
        case "compose_email":
            let to = listValue("to", in: arguments).joined(separator: ", ")
            let subject = (try? optionalStringValue("subject", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Compose Email", detail: "\(to)\n\(subject)", requiresConfirmation: true)
        case "send_email":
            let to = listValue("to", in: arguments).joined(separator: ", ")
            let subject = (try? optionalStringValue("subject", in: arguments)) ?? ""
            return AgentToolPreview(toolName: name, title: "Send Email", detail: "\(to)\n\(subject)", requiresConfirmation: true)
        case "mcp_list_servers":
            return AgentToolPreview(toolName: name, title: "List MCP Servers", detail: "Built-in and configured MCP servers", requiresConfirmation: false)
        case "mcp_list_tools":
            let server = (try? stringValue("server_id", in: arguments)) ?? "unknown server"
            return AgentToolPreview(toolName: name, title: "List MCP Tools", detail: server, requiresConfirmation: false)
        case "mcp_call_tool":
            let server = (try? stringValue("server_id", in: arguments)) ?? "unknown server"
            let tool = (try? stringValue("tool_name", in: arguments)) ?? "unknown tool"
            return AgentToolPreview(toolName: name, title: "Call MCP Tool", detail: "\(server): \(tool)", requiresConfirmation: true)
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
            "open", "run", "execute", "install", "build", "test", "fix",
            "send", "email", "mail", "browse", "browser", "github", "commit",
            "push", "pull request", "release", "mcp"
        ]

        let localTargets = [
            "file", "folder", "directory", "downloads", "desktop", "documents",
            "project", "app", "code", "terminal", "command", "script", "repo",
            "repository", "github", "browser", "safari", "chrome", "email",
            "mail", "mcp", "server", "website", "web page"
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
        ),
        OpenRouterTool(
            function: .init(
                name: "search_files",
                description: "Search for files or folders by name under a local root path.",
                parameters: .init(
                    properties: [
                        "root_path": .init(type: "string", description: "Root directory to search."),
                        "query": .init(type: "string", description: "Filename or path substring to find."),
                        "max_results": .init(type: "integer", description: "Optional result limit from 1 to 500.")
                    ],
                    required: ["root_path", "query"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "grep_text",
                description: "Search text contents under a local root path using ripgrep when available.",
                parameters: .init(
                    properties: [
                        "root_path": .init(type: "string", description: "Root directory to search."),
                        "pattern": .init(type: "string", description: "Literal or regex pattern to search for."),
                        "max_results": .init(type: "integer", description: "Optional output limit."),
                        "timeout_seconds": .init(type: "integer", description: "Optional timeout from 1 to 600 seconds.")
                    ],
                    required: ["root_path", "pattern"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "replace_in_text_file",
                description: "Replace text in a local UTF-8 text file.",
                parameters: .init(
                    properties: [
                        "path": .init(type: "string", description: "File path to edit."),
                        "find": .init(type: "string", description: "Exact text to find."),
                        "replacement": .init(type: "string", description: "Replacement text."),
                        "replace_all": .init(type: "boolean", description: "Whether to replace all occurrences. Defaults to false.")
                    ],
                    required: ["path", "find", "replacement"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "run_project_tests",
                description: "Run tests for a local project. Provide command for custom projects, or let CommandNest infer common runners.",
                parameters: .init(
                    properties: [
                        "project_path": .init(type: "string", description: "Project root path."),
                        "command": .init(type: "string", description: "Optional test command to run."),
                        "timeout_seconds": .init(type: "integer", description: "Optional timeout from 1 to 600 seconds.")
                    ],
                    required: ["project_path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "git_status",
                description: "Show git status for a local repository.",
                parameters: .init(
                    properties: [
                        "repository_path": .init(type: "string", description: "Local git repository path.")
                    ],
                    required: ["repository_path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "git_diff",
                description: "Show git diff and diff stat for a local repository.",
                parameters: .init(
                    properties: [
                        "repository_path": .init(type: "string", description: "Local git repository path."),
                        "pathspec": .init(type: "string", description: "Optional pathspec to limit the diff."),
                        "max_bytes": .init(type: "integer", description: "Optional output size limit.")
                    ],
                    required: ["repository_path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "git_commit",
                description: "Stage selected paths or all changes and create a git commit.",
                parameters: .init(
                    properties: [
                        "repository_path": .init(type: "string", description: "Local git repository path."),
                        "message": .init(type: "string", description: "Commit message."),
                        "paths": .init(type: "string", description: "Optional comma-separated path list. Stages all changes when omitted.")
                    ],
                    required: ["repository_path", "message"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "git_push",
                description: "Push a local git branch to a remote.",
                parameters: .init(
                    properties: [
                        "repository_path": .init(type: "string", description: "Local git repository path."),
                        "remote": .init(type: "string", description: "Optional remote name. Defaults to origin."),
                        "branch": .init(type: "string", description: "Optional branch name.")
                    ],
                    required: ["repository_path"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "github_create_pull_request",
                description: "Create a GitHub pull request with the gh CLI.",
                parameters: .init(
                    properties: [
                        "repository_path": .init(type: "string", description: "Local repository path."),
                        "title": .init(type: "string", description: "Pull request title."),
                        "body": .init(type: "string", description: "Pull request body."),
                        "base": .init(type: "string", description: "Optional base branch."),
                        "head": .init(type: "string", description: "Optional head branch."),
                        "draft": .init(type: "boolean", description: "Create a draft pull request. Defaults to true.")
                    ],
                    required: ["repository_path", "title"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "github_create_release",
                description: "Create a GitHub release with the gh CLI.",
                parameters: .init(
                    properties: [
                        "repository_path": .init(type: "string", description: "Local repository path."),
                        "tag": .init(type: "string", description: "Release tag."),
                        "title": .init(type: "string", description: "Optional release title."),
                        "notes": .init(type: "string", description: "Optional release notes."),
                        "asset_paths": .init(type: "string", description: "Optional comma-separated asset paths.")
                    ],
                    required: ["repository_path", "tag"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "browser_navigate",
                description: "Navigate Safari, Chrome, or the default browser to a URL.",
                parameters: .init(
                    properties: [
                        "url": .init(type: "string", description: "Full URL to open."),
                        "browser": .init(type: "string", description: "Optional browser: default, Safari, or Chrome.")
                    ],
                    required: ["url"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "browser_get_page_text",
                description: "Read visible text from the front Safari or Chrome tab using AppleScript JavaScript.",
                parameters: .init(
                    properties: [
                        "browser": .init(type: "string", description: "Optional browser: Safari or Chrome."),
                        "max_characters": .init(type: "integer", description: "Optional max characters to return.")
                    ],
                    required: []
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "browser_execute_javascript",
                description: "Execute JavaScript in the front Safari or Chrome tab.",
                parameters: .init(
                    properties: [
                        "browser": .init(type: "string", description: "Optional browser: Safari or Chrome."),
                        "javascript": .init(type: "string", description: "JavaScript to execute in the active tab.")
                    ],
                    required: ["javascript"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "search_web",
                description: "Open a web search in the default browser.",
                parameters: .init(
                    properties: [
                        "query": .init(type: "string", description: "Search query.")
                    ],
                    required: ["query"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "compose_email",
                description: "Open a mailto email draft in the user's mail app.",
                parameters: .init(
                    properties: [
                        "to": .init(type: "string", description: "Comma-separated recipient email addresses."),
                        "cc": .init(type: "string", description: "Optional comma-separated CC addresses."),
                        "bcc": .init(type: "string", description: "Optional comma-separated BCC addresses."),
                        "subject": .init(type: "string", description: "Email subject."),
                        "body": .init(type: "string", description: "Email body.")
                    ],
                    required: ["to"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "send_email",
                description: "Send an email through Apple Mail. This always requires user confirmation before sending.",
                parameters: .init(
                    properties: [
                        "to": .init(type: "string", description: "Comma-separated recipient email addresses."),
                        "cc": .init(type: "string", description: "Optional comma-separated CC addresses."),
                        "bcc": .init(type: "string", description: "Optional comma-separated BCC addresses."),
                        "subject": .init(type: "string", description: "Email subject."),
                        "body": .init(type: "string", description: "Email body."),
                        "attachment_paths": .init(type: "string", description: "Optional comma-separated local attachment paths.")
                    ],
                    required: ["to", "subject", "body"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "mcp_list_servers",
                description: "List built-in and user-configured MCP stdio servers available to CommandNest.",
                parameters: .init(properties: [:], required: [])
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "mcp_list_tools",
                description: "Connect to an MCP stdio server and list its tools.",
                parameters: .init(
                    properties: [
                        "server_id": .init(type: "string", description: "MCP server id from mcp_list_servers."),
                        "timeout_seconds": .init(type: "integer", description: "Optional timeout.")
                    ],
                    required: ["server_id"]
                )
            )
        ),
        OpenRouterTool(
            function: .init(
                name: "mcp_call_tool",
                description: "Call a tool on a configured MCP stdio server. This always requires confirmation because external MCP tools can perform arbitrary actions.",
                parameters: .init(
                    properties: [
                        "server_id": .init(type: "string", description: "MCP server id from mcp_list_servers."),
                        "tool_name": .init(type: "string", description: "MCP tool name."),
                        "arguments": .init(type: "object", description: "Tool arguments as a JSON object."),
                        "timeout_seconds": .init(type: "integer", description: "Optional timeout.")
                    ],
                    required: ["server_id", "tool_name", "arguments"]
                )
            )
        )
    ]
}

private struct MCPServerConfig {
    let id: String
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
}

private struct MCPConfigFile: Decodable {
    let mcpServers: [String: Server]

    struct Server: Decodable {
        let name: String?
        let command: String
        let args: [String]?
        let env: [String: String]?
    }
}

private struct MCPToolInfo {
    let name: String
    let description: String
}

private final class MCPStdioClient: @unchecked Sendable {
    private let config: MCPServerConfig
    private let timeout: TimeInterval

    init(config: MCPServerConfig, timeout: TimeInterval) {
        self.config = config
        self.timeout = timeout
    }

    func listTools() async throws -> [MCPToolInfo] {
        try await Task.detached {
            try self.withSession { session in
                let result = try session.request(method: "tools/list", params: [:])
                let tools = result["tools"] as? [[String: Any]] ?? []
                return tools.compactMap { tool in
                    guard let name = tool["name"] as? String else {
                        return nil
                    }
                    return MCPToolInfo(name: name, description: tool["description"] as? String ?? "")
                }
            }
        }.value
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        try await Task.detached {
            try self.withSession { session in
                let result = try session.request(
                    method: "tools/call",
                    params: [
                        "name": name,
                        "arguments": arguments
                    ]
                )
                return Self.renderToolResult(result)
            }
        }.value
    }

    private func withSession<T>(_ body: (MCPStdioSession) throws -> T) throws -> T {
        let session = try MCPStdioSession(config: config, timeout: timeout)
        defer {
            session.close()
        }

        try session.initialize()
        return try body(session)
    }

    private static func renderToolResult(_ result: [String: Any]) -> String {
        let isError = (result["isError"] as? Bool) == true
        let prefix = isError ? "MCP tool returned an error.\n" : ""
        guard let content = result["content"] as? [[String: Any]], !content.isEmpty else {
            return prefix + prettyJSON(result)
        }

        let rendered = content.map { item -> String in
            if let text = item["text"] as? String {
                return text
            }
            if let uri = item["uri"] as? String {
                return uri
            }
            return prettyJSON(item)
        }.joined(separator: "\n")

        return prefix + rendered
    }

    fileprivate static func prettyJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return text
    }
}

private final class MCPStdioSession {
    private let process: Process
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let timeout: TimeInterval
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var nextID = 1

    init(config: MCPServerConfig, timeout: TimeInterval) throws {
        self.timeout = timeout
        self.process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [config.command] + config.args.map(Self.expandedArgument)
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in config.env {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.lock.lock()
            self?.buffer.append(data)
            self?.lock.unlock()
            self?.semaphore.signal()
        }

        try process.run()
    }

    func initialize() throws {
        _ = try request(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": [
                    "name": "CommandNest",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                ]
            ]
        )
        try sendNotification(method: "notifications/initialized", params: [:])
    }

    func request(method: String, params: [String: Any]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ])

        let response = try readResponse(id: id)
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? MCPStdioClient.prettyJSON(error)
            throw AgentServiceError.invalidToolArguments("MCP \(method) failed: \(message)")
        }

        return response["result"] as? [String: Any] ?? [:]
    }

    func close() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try send([
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ])
    }

    private func send(_ message: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: message)
        let header = "Content-Length: \(body.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw AgentServiceError.invalidToolArguments("Could not encode MCP header.")
        }

        stdinPipe.fileHandleForWriting.write(headerData)
        stdinPipe.fileHandleForWriting.write(body)
    }

    private func readResponse(id: Int) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            while let message = popMessage() {
                if let messageID = message["id"] as? Int, messageID == id {
                    return message
                }
                if let messageID = message["id"] as? NSNumber, messageID.intValue == id {
                    return message
                }
            }

            let remaining = max(deadline.timeIntervalSinceNow, 0.05)
            if semaphore.wait(timeout: .now() + min(remaining, 0.25)) == .timedOut,
               !process.isRunning {
                let stderr = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                throw AgentServiceError.invalidToolArguments("MCP server exited before responding. \(stderr)")
            }
        }

        throw AgentServiceError.commandTimedOut
    }

    private func popMessage() -> [String: Any]? {
        lock.lock()
        defer {
            lock.unlock()
        }

        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: delimiter) else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8),
              let length = Self.contentLength(from: header) else {
            buffer.removeSubrange(0..<headerRange.upperBound)
            return nil
        }

        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + length
        guard buffer.count >= bodyEnd else {
            return nil
        }

        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(0..<bodyEnd)

        guard let object = try? JSONSerialization.jsonObject(with: body),
              let message = object as? [String: Any] else {
            return nil
        }

        return message
    }

    private static func contentLength(from header: String) -> Int? {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                continue
            }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func expandedArgument(_ argument: String) -> String {
        (argument as NSString).expandingTildeInPath
    }
}
