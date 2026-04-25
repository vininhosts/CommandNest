import XCTest
@testable import CommandNest

final class LocalActionServiceTests: XCTestCase {
    private var folder: URL!
    private var service: LocalActionService!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = fileManager.temporaryDirectory
            .appendingPathComponent("CommandNestTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        service = LocalActionService(fileManager: fileManager)
    }

    override func tearDownWithError() throws {
        if let folder {
            try? fileManager.removeItem(at: folder)
        }
        try super.tearDownWithError()
    }

    func testOrganizeFolderMovesLooseFilesByCategoryAndWritesManifest() async throws {
        try write("old", to: folder.appendingPathComponent("PDFs/report.pdf"))
        try write("new", to: folder.appendingPathComponent("report.pdf"))
        try write("png", to: folder.appendingPathComponent("photo.png"))
        try write("swift", to: folder.appendingPathComponent("app.swift"))
        try write("zip", to: folder.appendingPathComponent("bundle.zip"))
        try write("pkg", to: folder.appendingPathComponent("installer.pkg"))
        try write("misc", to: folder.appendingPathComponent("todo"))
        try write("partial", to: folder.appendingPathComponent("partial.download"))
        try fileManager.createDirectory(at: folder.appendingPathComponent("ExistingFolder"), withIntermediateDirectories: true)

        let response = try await service.handle(
            prompt: "organize files in \"\(folder.path)\"",
            onEvent: { _ in }
        )

        XCTAssertEqual(response?.contains("Organized 6 files"), true)
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("PDFs/report 2.pdf").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Images/photo.png").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Code/app.swift").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Archives/bundle.zip").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Installers/installer.pkg").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Other/todo").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("partial.download").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("ExistingFolder").path))

        let manifest = try latestManifestText()
        XCTAssertTrue(manifest.contains("\(folder.appendingPathComponent("report.pdf").path) -> "))
        XCTAssertTrue(manifest.contains("partial.download - incomplete download"))
    }

    func testUndoOrganizationRestoresFilesFromLatestManifest() async throws {
        try write("pdf", to: folder.appendingPathComponent("report.pdf"))
        try write("png", to: folder.appendingPathComponent("photo.png"))

        _ = try await service.handle(
            prompt: "organize files in \"\(folder.path)\"",
            onEvent: { _ in }
        )
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("report.pdf").path))

        let response = try await service.handle(
            prompt: "undo organization in \"\(folder.path)\"",
            onEvent: { _ in }
        )

        XCTAssertEqual(response?.contains("Restored 2 files"), true)
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("report.pdf").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("photo.png").path))
    }

    func testCreateFileCreatesParentDirectoriesAndContent() async throws {
        let destination = folder.appendingPathComponent("notes/today.md")

        let response = try await service.handle(
            prompt: "create a file called \"\(destination.path)\" that says \"hello from tests\"",
            onEvent: { _ in }
        )

        XCTAssertEqual(response?.contains(destination.path), true)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "hello from tests")
    }

    private func write(_ text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func latestManifestText() throws -> String {
        let manifestFolder = folder.appendingPathComponent(Constants.manifestFolderName, isDirectory: true)
        let manifests = try fileManager.contentsOfDirectory(
            at: manifestFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let manifest = try XCTUnwrap(manifests.max { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate < rhsDate
        })

        return try String(contentsOf: manifest, encoding: .utf8)
    }
}
