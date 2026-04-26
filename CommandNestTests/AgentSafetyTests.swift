import XCTest
@testable import CommandNest

final class AgentSafetyTests: XCTestCase {
    func testToolPreviewRequiresConfirmationForWritesAndShell() {
        let writeCall = OpenRouterToolCall(
            id: "call_1",
            type: "function",
            function: .init(
                name: "write_text_file",
                arguments: #"{"path":"~/Desktop/test.md","content":"hello"}"#
            )
        )
        let shellCall = OpenRouterToolCall(
            id: "call_2",
            type: "function",
            function: .init(
                name: "run_shell_command",
                arguments: #"{"command":"ls -la","working_directory":"~/Desktop"}"#
            )
        )

        XCTAssertTrue(AgentService.preview(for: writeCall).requiresConfirmation)
        XCTAssertTrue(AgentService.preview(for: shellCall).requiresConfirmation)
    }

    func testToolPreviewDoesNotRequireConfirmationForReadOnlyListing() {
        let call = OpenRouterToolCall(
            id: "call_1",
            type: "function",
            function: .init(
                name: "list_directory",
                arguments: #"{"path":"~/Downloads"}"#
            )
        )

        let preview = AgentService.preview(for: call)
        XCTAssertEqual(preview.title, "List Directory")
        XCTAssertFalse(preview.requiresConfirmation)
    }

    func testBlocksObviouslyDestructiveShellCommands() {
        XCTAssertTrue(AgentService.isBlockedShellCommand("rm -rf /"))
        XCTAssertTrue(AgentService.isBlockedShellCommand("diskutil eraseDisk APFS Blank /dev/disk2"))
        XCTAssertTrue(AgentService.isBlockedShellCommand("dd if=/dev/zero of=/dev/disk2"))
        XCTAssertFalse(AgentService.isBlockedShellCommand("find ~/Downloads -maxdepth 1 -type f"))
    }
}
