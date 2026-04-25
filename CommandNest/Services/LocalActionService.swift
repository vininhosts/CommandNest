import Foundation

protocol LocalActionServicing {
    func handle(
        prompt: String,
        onEvent: @escaping @MainActor (String) -> Void
    ) async throws -> String?
}

enum LocalActionError: LocalizedError {
    case folderUnavailable(String)
    case manifestUnavailable(String)
    case unsupportedCreateFilePrompt

    var errorDescription: String? {
        switch self {
        case .folderUnavailable(let path):
            return "I could not access \(path). Check Full Disk Access in Settings."
        case .manifestUnavailable(let path):
            return "I could not find an organization manifest in \(path)."
        case .unsupportedCreateFilePrompt:
            return "Tell me the filename to create, for example: create a file called notes.md that says hello."
        }
    }
}

final class LocalActionService: LocalActionServicing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func handle(
        prompt: String,
        onEvent: @escaping @MainActor (String) -> Void
    ) async throws -> String? {
        let normalized = prompt.lowercased()

        if shouldUndoOrganization(normalized) {
            await onEvent("Undoing organization")
            let folder = try targetFolder(from: prompt, normalizedPrompt: normalized)
            return try undoLastOrganization(in: folder)
        }

        if shouldOrganizeFiles(normalized) {
            await onEvent("Organizing files")
            let folder = try targetFolder(from: prompt, normalizedPrompt: normalized)
            return try organizeFolder(folder)
        }

        if shouldCreateFile(normalized) {
            await onEvent("Creating file")
            return try createTextFile(from: prompt)
        }

        return nil
    }

    private func shouldOrganizeFiles(_ prompt: String) -> Bool {
        let hasAction = prompt.contains("organize")
            || prompt.contains("organise")
            || prompt.contains("sort")
            || prompt.contains("clean up")
            || prompt.contains("cleanup")
        let hasTarget = prompt.contains("file")
            || prompt.contains("folder")
            || prompt.contains("downloads")
            || prompt.contains("desktop")
            || prompt.contains("documents")
            || prompt.contains("/")
            || prompt.contains("~/")

        return hasAction && hasTarget
    }

    private func shouldUndoOrganization(_ prompt: String) -> Bool {
        let hasUndo = prompt.contains("undo")
            || prompt.contains("revert")
            || prompt.contains("put back")
        let hasOrganization = prompt.contains("organize")
            || prompt.contains("organise")
            || prompt.contains("organization")
            || prompt.contains("organisation")
            || prompt.contains("sorting")

        return hasUndo && hasOrganization
    }

    private func shouldCreateFile(_ prompt: String) -> Bool {
        (prompt.contains("create") || prompt.contains("make") || prompt.contains("write"))
            && prompt.contains("file")
    }

    private func targetFolder(from prompt: String, normalizedPrompt: String) throws -> URL {
        if let quotedPath = firstQuotedPath(in: prompt) {
            return URL(fileURLWithPath: expandedPath(quotedPath))
        }

        let directory: FileManager.SearchPathDirectory
        if normalizedPrompt.contains("desktop") {
            directory = .desktopDirectory
        } else if normalizedPrompt.contains("documents") {
            directory = .documentDirectory
        } else {
            directory = .downloadsDirectory
        }

        guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
            throw LocalActionError.folderUnavailable(directory.defaultDisplayName)
        }

        return url
    }

    private func organizeFolder(_ folder: URL) throws -> String {
        guard fileManager.fileExists(atPath: folder.path) else {
            throw LocalActionError.folderUnavailable(folder.path)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        )

        var moves: [(from: URL, to: URL)] = []
        var skipped: [String] = []
        var categoryCounts: [String: Int] = [:]

        for item in contents {
            let name = item.lastPathComponent

            do {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])

                if values.isHidden == true || values.isDirectory == true || name.hasPrefix(".") {
                    continue
                }

                let ext = item.pathExtension.lowercased()
                if ["download", "crdownload", "part"].contains(ext) {
                    skipped.append("\(name) - incomplete download")
                    continue
                }

                let category = categoryName(forExtension: ext)
                let categoryURL = folder.appendingPathComponent(category, isDirectory: true)
                try fileManager.createDirectory(at: categoryURL, withIntermediateDirectories: true)

                let destination = uniqueDestination(for: item.lastPathComponent, in: categoryURL)
                try fileManager.moveItem(at: item, to: destination)

                moves.append((item, destination))
                categoryCounts[category, default: 0] += 1
            } catch {
                skipped.append("\(name) - \(error.localizedDescription)")
            }
        }

        let manifestURL = try writeManifest(for: folder, moves: moves, skipped: skipped)

        guard !moves.isEmpty else {
            return "I checked \(folder.path), but there were no loose files to move. Directories and hidden files were left alone."
        }

        let categorySummary = categoryCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")

        return """
        Organized \(moves.count) files in \(folder.path).

        \(categorySummary)

        Manifest:
        \(manifestURL.path)
        """
    }

    private func undoLastOrganization(in folder: URL) throws -> String {
        guard fileManager.fileExists(atPath: folder.path) else {
            throw LocalActionError.folderUnavailable(folder.path)
        }

        guard let manifestURL = try latestManifest(in: folder) else {
            throw LocalActionError.manifestUnavailable(folder.path)
        }

        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let moves = parseMoves(from: manifest)

        guard !moves.isEmpty else {
            return "The latest manifest did not contain any moved files: \(manifestURL.path)."
        }

        var restored = 0
        var skipped: [String] = []

        for move in moves.reversed() {
            guard fileManager.fileExists(atPath: move.to.path) else {
                skipped.append("\(move.to.path) - destination no longer exists")
                continue
            }

            guard !fileManager.fileExists(atPath: move.from.path) else {
                skipped.append("\(move.from.path) - original path already exists")
                continue
            }

            do {
                try fileManager.createDirectory(at: move.from.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: move.to, to: move.from)
                restored += 1
            } catch {
                skipped.append("\(move.to.path) - \(error.localizedDescription)")
            }
        }

        let skippedSummary = skipped.isEmpty
            ? ""
            : "\n\nSkipped:\n\(skipped.joined(separator: "\n"))"

        return """
        Restored \(restored) files using:
        \(manifestURL.path)\(skippedSummary)
        """
    }

    private func createTextFile(from prompt: String) throws -> String {
        guard let filePath = requestedFilePath(from: prompt) else {
            throw LocalActionError.unsupportedCreateFilePrompt
        }

        let content = requestedFileContent(from: prompt) ?? ""
        let destination: URL
        if filePath.hasPrefix("/") || filePath.hasPrefix("~") {
            destination = URL(fileURLWithPath: expandedPath(filePath))
        } else {
            let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
            destination = desktop.appendingPathComponent(filePath)
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let finalURL = fileManager.fileExists(atPath: destination.path)
            ? uniqueDestination(for: destination.lastPathComponent, in: destination.deletingLastPathComponent())
            : destination
        try content.write(to: finalURL, atomically: true, encoding: .utf8)

        return "Created \(finalURL.path)."
    }

    private func categoryName(forExtension ext: String) -> String {
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "tif", "bmp", "svg":
            return "Images"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv":
            return "Videos"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff":
            return "Audio"
        case "pdf":
            return "PDFs"
        case "doc", "docx", "txt", "rtf", "md", "pages", "odt":
            return "Documents"
        case "xls", "xlsx", "csv", "tsv", "numbers", "ods":
            return "Spreadsheets"
        case "ppt", "pptx", "key", "odp":
            return "Presentations"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso":
            return "Archives"
        case "pkg", "mpkg":
            return "Installers"
        case "swift", "py", "js", "ts", "tsx", "jsx", "html", "css", "json", "yaml", "yml", "xml", "java", "c", "cpp", "h", "rb", "go", "rs", "php", "sql", "sh", "command":
            return "Code"
        case "ttf", "otf", "woff", "woff2":
            return "Fonts"
        default:
            return "Other"
        }
    }

    private func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let original = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: original.path) else {
            return original
        }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        for index in 2...999 {
            let candidateName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    }

    private func writeManifest(for folder: URL, moves: [(from: URL, to: URL)], skipped: [String]) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let manifestFolder = folder.appendingPathComponent(Constants.manifestFolderName, isDirectory: true)
        try fileManager.createDirectory(at: manifestFolder, withIntermediateDirectories: true)

        let manifestURL = manifestFolder.appendingPathComponent("organization-\(formatter.string(from: Date())).txt")
        var lines = [
            "\(Constants.appName) organization manifest",
            "Folder: \(folder.path)",
            "Created: \(Date())",
            ""
        ]

        if moves.isEmpty {
            lines.append("No files moved.")
        } else {
            lines.append("Moved files:")
            lines.append(contentsOf: moves.map { "\($0.from.path) -> \($0.to.path)" })
        }

        if !skipped.isEmpty {
            lines.append("")
            lines.append("Skipped:")
            lines.append(contentsOf: skipped)
        }

        try lines.joined(separator: "\n").write(to: manifestURL, atomically: true, encoding: .utf8)
        return manifestURL
    }

    private func latestManifest(in folder: URL) throws -> URL? {
        let manifestFolders = [
            folder.appendingPathComponent(Constants.manifestFolderName, isDirectory: true),
            folder.appendingPathComponent(Constants.legacyManifestFolderName, isDirectory: true)
        ]

        var manifests: [URL] = []
        for manifestFolder in manifestFolders where fileManager.fileExists(atPath: manifestFolder.path) {
            let folderManifests = try fileManager.contentsOfDirectory(
                at: manifestFolder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "txt" }
            manifests.append(contentsOf: folderManifests)
        }

        return try manifests.max { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private func parseMoves(from manifest: String) -> [(from: URL, to: URL)] {
        manifest
            .components(separatedBy: .newlines)
            .compactMap { line -> (from: URL, to: URL)? in
                let parts = line.components(separatedBy: " -> ")
                guard parts.count == 2 else {
                    return nil
                }

                return (
                    URL(fileURLWithPath: parts[0]),
                    URL(fileURLWithPath: parts[1])
                )
            }
    }

    private func requestedFilePath(from prompt: String) -> String? {
        if let quoted = firstQuotedPath(in: prompt), looksLikeFilePath(quoted) {
            return quoted
        }

        let patterns = [
            #"(?i)(?:called|named)\s+([^\s]+\.[A-Za-z0-9]{1,12})"#,
            #"(?i)file\s+([^\s]+\.[A-Za-z0-9]{1,12})"#
        ]

        for pattern in patterns {
            if let match = firstRegexCapture(pattern, in: prompt) {
                return match
            }
        }

        return nil
    }

    private func requestedFileContent(from prompt: String) -> String? {
        let patterns = [
            #"(?is)(?:with content|that says|containing)\s+["“](.*?)["”]"#,
            #"(?is)(?:with content|that says|containing)\s+(.+)$"#
        ]

        for pattern in patterns {
            if let match = firstRegexCapture(pattern, in: prompt) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private func firstQuotedPath(in text: String) -> String? {
        let pattern = #"["“']([^"”']+)["”']"#
        return firstRegexCapture(pattern, in: text)
    }

    private func firstRegexCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }

    private func looksLikeFilePath(_ text: String) -> Bool {
        !URL(fileURLWithPath: text).pathExtension.isEmpty
    }

    private func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

private extension FileManager.SearchPathDirectory {
    var defaultDisplayName: String {
        switch self {
        case .downloadsDirectory:
            return "Downloads"
        case .desktopDirectory:
            return "Desktop"
        case .documentDirectory:
            return "Documents"
        default:
            return "the requested folder"
        }
    }
}
