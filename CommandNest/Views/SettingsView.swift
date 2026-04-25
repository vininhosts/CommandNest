import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var isRecordingShortcut = false

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.largeTitle.weight(.semibold))

                    GroupBox("OpenRouter") {
                        VStack(alignment: .leading, spacing: 10) {
                            SecureField("OpenRouter API key", text: $viewModel.apiKey)
                                .textFieldStyle(.roundedBorder)
                            Text("Stored securely in macOS Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Models") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $viewModel.modelListText)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 105)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )

                            HStack {
                                Picker("Default model", selection: $viewModel.selectedModel) {
                                    ForEach(viewModel.parsedModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .frame(maxWidth: 360)

                                Spacer()

                                Button {
                                    Task {
                                        await viewModel.refreshModelsFromOpenRouter()
                                    }
                                } label: {
                                    if viewModel.isRefreshingModels {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Text("Load All")
                                    }
                                }
                                .disabled(viewModel.isRefreshingModels)

                                Button("Reset Models") {
                                    viewModel.resetModels()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Agent Access") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable local agent mode", isOn: $viewModel.agentModeEnabled)
                                .toggleStyle(.checkbox)

                            Text("When enabled, the assistant can ask the model to read and write local files, run shell commands, and open files, apps, or URLs. macOS may still require privacy permissions for protected locations and desktop control.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                Button("Full Disk Access") {
                                    PermissionService.openFullDiskAccessSettings()
                                }

                                Button(PermissionService.isAccessibilityTrusted ? "Accessibility Granted" : "Request Accessibility") {
                                    PermissionService.requestAccessibility()
                                    PermissionService.openAccessibilitySettings()
                                }

                                Button(PermissionService.hasScreenRecordingAccess ? "Screen Recording Granted" : "Request Screen Recording") {
                                    PermissionService.requestScreenRecording()
                                    PermissionService.openScreenRecordingSettings()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Behavior") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("System prompt")
                                    .font(.headline)
                                TextEditor(text: $viewModel.systemPrompt)
                                    .frame(height: 74)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                            }

                            HStack(spacing: 12) {
                                Text("Global shortcut")
                                    .font(.headline)
                                    .frame(width: 120, alignment: .leading)

                                ShortcutRecorderView(
                                    shortcut: $viewModel.shortcut,
                                    isRecording: $isRecordingShortcut
                                )
                                .frame(width: 240, height: 34)

                                Text("Uses macOS global hotkeys and normally requires no Accessibility permission.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let status = viewModel.statusMessage {
                    Label(status, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }

                Spacer()

                Button("Save Settings") {
                    viewModel.save()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 700, height: 760)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalKeyboardShortcut
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderControl {
        let control = RecorderControl()
        control.shortcut = shortcut
        control.isRecording = isRecording
        control.onShortcutChange = { shortcut in
            self.shortcut = shortcut
        }
        control.onRecordingChange = { isRecording in
            self.isRecording = isRecording
        }
        return control
    }

    func updateNSView(_ nsView: RecorderControl, context: Context) {
        nsView.shortcut = shortcut
        nsView.isRecording = isRecording
        nsView.needsDisplay = true

        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class RecorderControl: NSView {
        var shortcut: GlobalKeyboardShortcut = .defaultShortcut
        var isRecording = false
        var onShortcutChange: ((GlobalKeyboardShortcut) -> Void)?
        var onRecordingChange: ((Bool) -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            isRecording = true
            onRecordingChange?(true)
            window?.makeFirstResponder(self)
            needsDisplay = true
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                onRecordingChange?(false)
                needsDisplay = true
                return
            }

            guard let capturedShortcut = GlobalKeyboardShortcut(event: event) else {
                NSSound.beep()
                return
            }

            shortcut = capturedShortcut
            isRecording = false
            onShortcutChange?(capturedShortcut)
            onRecordingChange?(false)
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            let text = isRecording ? "Press shortcut..." : shortcut.displayString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textRect = NSRect(
                x: bounds.minX + 12,
                y: bounds.midY - attributed.size().height / 2,
                width: bounds.width - 24,
                height: attributed.size().height
            )
            attributed.draw(in: textRect)
        }
    }
}
