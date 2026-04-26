import Foundation

struct ReasoningParseResult: Equatable {
    var answer: String = ""
    var reasoning: String = ""
}

struct ReasoningTextParser {
    private var buffer = ""
    private var isInsideReasoning = false
    private let retainedTailLength = 24

    mutating func consume(_ text: String) -> ReasoningParseResult {
        guard !text.isEmpty else {
            return ReasoningParseResult()
        }

        buffer += text
        return drainBuffer(keepTail: true)
    }

    mutating func finish() -> ReasoningParseResult {
        drainBuffer(keepTail: false)
    }

    static func separate(answer rawAnswer: String, explicitReasoning: String = "") -> ReasoningParseResult {
        var parser = ReasoningTextParser()
        var result = parser.consume(rawAnswer)
        let tail = parser.finish()
        result.answer += tail.answer
        result.reasoning += tail.reasoning

        if !explicitReasoning.isEmpty {
            result.reasoning = [explicitReasoning, result.reasoning]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        }

        result.answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        result.reasoning = result.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private mutating func drainBuffer(keepTail: Bool) -> ReasoningParseResult {
        var result = ReasoningParseResult()

        while !buffer.isEmpty {
            if isInsideReasoning {
                if let range = firstTagRange(in: buffer, tags: ["</think>", "</thinking>"]) {
                    result.reasoning += String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(..<range.upperBound)
                    isInsideReasoning = false
                    continue
                }

                let drained = drainablePrefix(keepTail: keepTail)
                result.reasoning += drained
                if drained.isEmpty {
                    break
                }
            } else {
                if let range = firstTagRange(in: buffer, tags: ["<think>", "<thinking>"]) {
                    result.answer += String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(..<range.upperBound)
                    isInsideReasoning = true
                    continue
                }

                let drained = drainablePrefix(keepTail: keepTail)
                result.answer += drained
                if drained.isEmpty {
                    break
                }
            }
        }

        return result
    }

    private func firstTagRange(in text: String, tags: [String]) -> Range<String.Index>? {
        tags
            .compactMap { tag in
                text.range(of: tag, options: [.caseInsensitive])
            }
            .min { first, second in
                first.lowerBound < second.lowerBound
            }
    }

    private mutating func drainablePrefix(keepTail: Bool) -> String {
        guard keepTail else {
            let drained = buffer
            buffer.removeAll(keepingCapacity: true)
            return drained
        }

        guard buffer.count > retainedTailLength else {
            return ""
        }

        let splitIndex = buffer.index(buffer.endIndex, offsetBy: -retainedTailLength)
        let drained = String(buffer[..<splitIndex])
        buffer.removeSubrange(..<splitIndex)
        return drained
    }
}
