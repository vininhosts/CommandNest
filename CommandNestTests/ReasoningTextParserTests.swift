import XCTest
@testable import CommandNest

final class ReasoningTextParserTests: XCTestCase {
    func testSeparatesThinkBlocksFromAnswer() {
        let result = ReasoningTextParser.separate(answer: "<think>plan quietly</think>\nFinal **answer**.")

        XCTAssertEqual(result.answer, "Final **answer**.")
        XCTAssertEqual(result.reasoning, "plan quietly")
    }

    func testHandlesSplitTagsAcrossStreamingChunks() {
        var parser = ReasoningTextParser()
        var answer = ""
        var reasoning = ""

        for chunk in ["<thi", "nk>step", " one</th", "ink>Done"] {
            let parsed = parser.consume(chunk)
            answer += parsed.answer
            reasoning += parsed.reasoning
        }

        let tail = parser.finish()
        answer += tail.answer
        reasoning += tail.reasoning

        XCTAssertEqual(answer, "Done")
        XCTAssertEqual(reasoning, "step one")
    }

    func testExplicitReasoningIsCombinedWithTaggedReasoning() {
        let result = ReasoningTextParser.separate(
            answer: "<thinking>tagged</thinking>Visible",
            explicitReasoning: "provider reasoning"
        )

        XCTAssertEqual(result.answer, "Visible")
        XCTAssertEqual(result.reasoning, "provider reasoning\n\ntagged")
    }
}
