import AppKit
import Carbon
import SwiftUI

struct AssistantWindowView: View {
    @ObservedObject var viewModel: AssistantViewModel
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header

            Divider()

            conversation

            promptEditor

            footer
        }
        .padding(18)
        .frame(width: 760, height: 600)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 30, x: 0, y: 18)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(Constants.appName)
                .font(.headline)

            Spacer()

            ModelPickerView(selectedModel: $viewModel.selectedModel, models: viewModel.availableModels)
                .disabled(viewModel.isSending)

            Button {
                viewModel.copyLastResponse()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy full assistant response")
            .disabled(viewModel.lastAssistantResponse.isEmpty)

            Button {
                viewModel.clearConversation()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear conversation")
            .disabled(viewModel.isSending)

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .buttonStyle(.borderless)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.visibleMessages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Ask anything")
                                .font(.title3.weight(.semibold))
                            Text("Option + Space opens this assistant from anywhere.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(viewModel.visibleMessages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.messages) { _, messages in
                guard let lastID = messages.last?.id else {
                    return
                }

                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var promptEditor: some View {
        PromptTextView(
            text: $viewModel.prompt,
            isDisabled: viewModel.isSending,
            onSubmit: {
                Task {
                    await viewModel.sendPrompt()
                }
            }
        )
        .frame(height: 86)
        .padding(10)
        .background(Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if viewModel.isSending {
                ProgressView()
                    .scaleEffect(0.72)
                Text("Streaming")
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter sends. Shift + Enter adds a line.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.sendPrompt()
                }
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .font(.callout)
    }
}

private struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    let isDisabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = SubmittingTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.string = text
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmittingTextView else {
            return
        }

        textView.onSubmit = onSubmit
        textView.isEditable = !isDisabled
        if textView.string != text {
            textView.string = text
        }

        DispatchQueue.main.async {
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }
    }

    final class SubmittingTextView: NSTextView {
        var onSubmit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                    super.keyDown(with: event)
                } else {
                    onSubmit?()
                }
                return
            }

            super.keyDown(with: event)
        }
    }
}
