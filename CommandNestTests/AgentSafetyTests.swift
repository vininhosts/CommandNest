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

    func testHighImpactAgentToolsRequireConfirmation() {
        let toolCalls = [
            OpenRouterToolCall(
                id: "call_email",
                type: "function",
                function: .init(
                    name: "send_email",
                    arguments: #"{"to":"person@example.com","subject":"Hello","body":"Hi"}"#
                )
            ),
            OpenRouterToolCall(
                id: "call_gmail",
                type: "function",
                function: .init(
                    name: "gmail_send_email",
                    arguments: #"{"to":"person@example.com","subject":"Hello","body":"Hi"}"#
                )
            ),
            OpenRouterToolCall(
                id: "call_browser",
                type: "function",
                function: .init(
                    name: "browser_execute_javascript",
                    arguments: #"{"browser":"Safari","javascript":"document.title"}"#
                )
            ),
            OpenRouterToolCall(
                id: "call_browser_read",
                type: "function",
                function: .init(
                    name: "browser_get_page_text",
                    arguments: #"{"browser":"Safari"}"#
                )
            ),
            OpenRouterToolCall(
                id: "call_pr",
                type: "function",
                function: .init(
                    name: "github_create_pull_request",
                    arguments: #"{"repository_path":"~/Project","title":"Update"}"#
                )
            ),
            OpenRouterToolCall(
                id: "call_mcp",
                type: "function",
                function: .init(
                    name: "mcp_call_tool",
                    arguments: #"{"server_id":"filesystem","tool_name":"write_file","arguments":{"path":"~/Desktop/a.txt","content":"x"}}"#
                )
            )
        ]

        for toolCall in toolCalls {
            XCTAssertTrue(AgentService.preview(for: toolCall).requiresConfirmation, "\(toolCall.function.name) should require confirmation")
        }
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
