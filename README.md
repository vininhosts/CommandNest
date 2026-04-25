# CommandNest

CommandNest is a lightweight native macOS menu bar assistant. Press `Option + Space`, type a prompt, and get a streamed OpenRouter response in a floating command palette. When a request is clearly local, CommandNest can also act on your Mac: organize files, create files, inspect folders, run shell commands, and open items.

## Features

- Native Swift, SwiftUI, and AppKit for macOS 14+
- Global Carbon hotkey with default `Option + Space`
- Floating always-on-top assistant panel with dark/light mode support
- OpenRouter Chat Completions integration with streaming SSE parsing
- Non-streaming fallback if streaming fails before any output arrives
- OpenRouter model catalog loading from `/api/v1/models`
- Free Models Router default model: `openrouter/free`
- API key stored in macOS Keychain
- In-memory conversation with editable system prompt
- Menu bar app behavior using `LSUIElement`
- Local Agent Mode with filesystem, shell, and open-item tools
- Native local actions for organizing folders, undoing organization, and creating text files
- Settings for API key, model list, selected model, system prompt, agent access, and shortcut recording

## Download Without Xcode

Download the latest `CommandNest-<version>-<build>.zip` from GitHub Releases:

```text
https://github.com/vininhosts/CommandNest/releases
```

Then:

1. Unzip the file.
2. Move `CommandNest.app` to `/Applications`.
3. Open `CommandNest.app`.
4. If macOS blocks the first launch, right-click `CommandNest.app`, choose `Open`, then confirm.

The downloadable build does not require Xcode. This repository also includes a packaging script for maintainers:

```sh
Scripts/package_release.sh
```

Public release builds are ad-hoc signed unless a maintainer builds with a Developer ID certificate. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for signing and notarization notes.

## Build and Run

1. Open `CommandNest.xcodeproj` in Xcode 15 or newer.
2. Select the `CommandNest` scheme.
3. Build and run on macOS 14 or newer.
4. The app appears in the menu bar, not the Dock.

From Terminal:

```sh
xcodebuild -project CommandNest.xcodeproj -scheme CommandNest -configuration Debug -destination 'platform=macOS' build
```

After building, copy it into Applications and launch it like a normal app:

```sh
ditto ~/Library/Developer/Xcode/DerivedData/CommandNest-*/Build/Products/Debug/CommandNest.app /Applications/CommandNest.app
open /Applications/CommandNest.app
```

## Add Your OpenRouter API Key

1. Run the app.
2. Click the CommandNest menu bar icon.
3. Choose `Settings`.
4. Paste your OpenRouter API key into the secure field.
5. Click `Save Settings`.

The key is saved as a generic password in macOS Keychain. It is never hardcoded or written to `UserDefaults`. Existing keys saved by earlier ShortcutAI builds are migrated automatically on first read.

## Global Shortcut Permissions

CommandNest uses `RegisterEventHotKey`, the standard macOS global hotkey API. This normally does not require Accessibility or Input Monitoring permission. If macOS or another app already owns the chosen shortcut, CommandNest shows an error and you can record a different shortcut in Settings.

## OpenRouter

Requests are sent to:

```text
https://openrouter.ai/api/v1/chat/completions
```

Headers include:

```text
Authorization: Bearer <OPENROUTER_API_KEY>
Content-Type: application/json
HTTP-Referer: https://github.com/local/CommandNest
X-Title: CommandNest
```

Default models start with the free router:

- `openrouter/free`

CommandNest also loads the current OpenRouter model catalog from:

```text
https://openrouter.ai/api/v1/models
```

The Settings window has a `Load All` button to refresh the editable model list. On launch, the app also refreshes the model list in the background.

Bundled fallback models:

- `openai/gpt-4o-mini`
- `anthropic/claude-3.5-haiku`
- `google/gemini-flash-1.5`
- `meta-llama/llama-3.1-8b-instruct`

## Local Agent Mode

Settings includes `Enable local agent mode`, which is on by default for agent-like behavior. Normal chat still streams. CommandNest switches to local agent mode only when the prompt looks like a file, folder, app, code, shell, or Mac action.

When local agent mode is used, the selected OpenRouter model can ask CommandNest to:

- List directories
- Read text files
- Write text files
- Create directories
- Move or rename files and folders
- Copy files and folders
- Move files and folders to Trash
- Run `zsh` shell commands
- Open files, folders, apps, or URLs

CommandNest also has native local actions that run before the model is called and do not require an API key:

```text
organize my Downloads
organize my Desktop
organize files in "/Users/you/some-folder"
undo organization in "/Users/you/some-folder"
create a file called notes.md that says hello
```

`organize my files` defaults to the Downloads folder. It moves loose files into category folders, skips hidden files, directories, and incomplete downloads, avoids overwriting with numbered names, and writes a manifest under `CommandNest-Manifests`. `undo organization` uses the latest manifest to move files back when the original path is still free.

This is intentionally powerful. It runs on your Mac, outside the App Sandbox, and uses your current user account. macOS still protects some areas until you grant permissions.

Useful permissions:

- Full Disk Access: needed for broad file access, including protected folders.
- Accessibility: needed for future desktop/UI control workflows and some automation.
- Screen Recording: needed for future screen-aware workflows.

CommandNest cannot grant these permissions to itself. Use the buttons in Settings to open the correct System Settings panes, then enable CommandNest.

## Tests

```sh
xcodebuild -project CommandNest.xcodeproj -scheme CommandNest -configuration Debug -destination 'platform=macOS' test
```

The current test target covers settings migrations, model normalization, local file creation, folder organization, manifest writing, conflict-safe moves, skipped incomplete downloads, and undoing organization from a manifest.

## Open Source

- License: MIT
- Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md)
- Security: see [SECURITY.md](SECURITY.md)
- Privacy: see [PRIVACY.md](PRIVACY.md)
- Distribution: see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)

## Project Structure

```text
CommandNest/
├── CommandNestApp.swift
├── AppDelegate.swift
├── Models/
│   ├── ChatMessage.swift
│   └── AppSettings.swift
├── Services/
│   ├── OpenRouterClient.swift
│   ├── KeychainService.swift
│   ├── HotKeyService.swift
│   ├── AgentService.swift
│   ├── LocalActionService.swift
│   └── PermissionService.swift
├── ViewModels/
│   ├── AssistantViewModel.swift
│   └── SettingsViewModel.swift
├── Views/
│   ├── AssistantWindowView.swift
│   ├── SettingsView.swift
│   ├── MessageBubbleView.swift
│   └── ModelPickerView.swift
└── Utilities/
    ├── ClipboardHelper.swift
    └── Constants.swift
CommandNestTests/
├── AppSettingsTests.swift
└── LocalActionServiceTests.swift
```

## Info.plist and Entitlements

`Info.plist` sets `LSUIElement` to `true`, so CommandNest runs as a menu bar app without a Dock icon. The included entitlements file is intentionally empty because the app is not sandboxed by default. If you enable App Sandbox later, add the outbound network client entitlement and revisit local agent capabilities.
