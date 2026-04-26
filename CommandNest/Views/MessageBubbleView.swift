import Foundation
import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var isReasoningExpanded = false

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if message.role == .assistant, !message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    thinkingView
                }

                Text(renderMarkdown(message.content.isEmpty ? "Thinking..." : message.content))
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 48)
            }
        }
    }

    private var thinkingView: some View {
        DisclosureGroup(isExpanded: $isReasoningExpanded) {
            Text(renderMarkdown(message.reasoning))
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Thinking", systemImage: "lightbulb")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var background: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }

        return AnyShapeStyle(Color.secondary.opacity(0.10))
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
