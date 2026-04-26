import SwiftUI

struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to \(Constants.appName)")
                        .font(.largeTitle.weight(.semibold))
                    Text("A native command palette for OpenRouter and local Mac actions.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("Add your OpenRouter API key in Settings.", systemImage: "key")
                Label("Press Option + Space to open the assistant.", systemImage: "keyboard")
                Label("Review each local file, app, or shell action before it runs.", systemImage: "checkmark.shield")
                Label("Grant macOS privacy permissions only for folders you ask it to use.", systemImage: "folder.badge.gearshape")
            }
            .font(.callout)

            Spacer()

            HStack {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Start Using CommandNest") {
                    onContinue()
                }
            }
        }
        .padding(26)
        .frame(width: 560, height: 400)
    }
}
