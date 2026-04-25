import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            Text(message.content.isEmpty ? "Thinking..." : message.content)
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
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

    private var background: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }

        return AnyShapeStyle(Color.secondary.opacity(0.10))
    }
}
