# CommandNest

[![Latest release](https://img.shields.io/github/v/release/vininhosts/CommandNest?style=flat-square)](https://github.com/vininhosts/CommandNest/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/vininhosts/CommandNest/total?style=flat-square)](https://github.com/vininhosts/CommandNest/releases)
[![macOS CI](https://img.shields.io/github/actions/workflow/status/vininhosts/CommandNest/ci.yml?branch=main&label=macOS%20CI&style=flat-square)](https://github.com/vininhosts/CommandNest/actions/workflows/ci.yml)
[![Windows/Linux](https://img.shields.io/github/actions/workflow/status/vininhosts/CommandNest/cross-platform.yml?branch=main&label=Windows%20%2F%20Linux&style=flat-square)](https://github.com/vininhosts/CommandNest/actions/workflows/cross-platform.yml)
[![License](https://img.shields.io/github/license/vininhosts/CommandNest?style=flat-square)](LICENSE)

CommandNest is a lightweight desktop AI assistant. The primary app is a native macOS menu bar assistant: press `Option + Space`, type a prompt, and get a streamed OpenRouter response in a floating command palette. When a request is clearly local, CommandNest can also act on your Mac: organize files, create and edit code, run tests, control browsers, prepare or send email, use git/GitHub, run shell commands, and call MCP servers. A Windows/Linux Electron edition lives in `CrossPlatform/`.

Website: [vininhosts.github.io/CommandNest](https://vininhosts.github.io/CommandNest/)

## Features

- Native Swift, SwiftUI, and AppKit for macOS 14+
- Global Carbon hotkey with default `Option + Space`
- Floating always-on-top assistant panel with dark/light mode support
- OpenRouter Chat Completions integration with streaming SSE parsing
- Non-streaming fallback if streaming fails before any output arrives
- OpenRouter model catalog loading from `/api/v1/models`
- Free Models Router default model: `openrouter/free`
- Searchable model picker in the assistant and Settings
- Markdown response rendering, so formatted answers do not show raw `**` markers
- Collapsible Thinking panel for provider reasoning and `<think>...</think>` output
- API key stored in macOS Keychain
- In-memory conversation with editable system prompt
- Menu bar app behavior using `LSUIElement`
- Local Agent Mode with filesystem, coding, shell, browser, email, git/GitHub, and MCP tools
- Native local actions for organizing folders, undoing organization, and creating text files
- Settings for API key, model list, selected model, system prompt, agent access, launch at login, and shortcut recording

## Download Without Xcode

Download the latest release from GitHub:

```text
https://github.com/vininhosts/CommandNest/releases/latest
```

Quick install:

```sh
curl -fsSL https://raw.githubusercontent.com/vininhosts/CommandNest/main/Scripts/install-macos.sh | bash
```

Manual install:

1. Unzip the file.
2. Move `CommandNest.app` to `/Applications`.
3. Open `CommandNest.app`.
4. If macOS blocks the first launch, right-click `CommandNest.app`, choose `Open`, then confirm.

The downloadable build does not require Xcode. This repository also includes a packaging script for maintainers:

```sh
Scripts/package_release.sh
```

Public release builds are ad-hoc signed unless a maintainer builds with a Developer ID certificate. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for signing and notarization notes.

## Windows and Linux

The `CrossPlatform/` folder contains an Electron edition for Windows and Linux with the same core behavior: tray app, global `Alt+Space` shortcut, floating assistant palette, secure API key storage with OS secure storage, streamed OpenRouter responses, searchable models, Thinking panel, launch at login, and local agent tools.

Install on Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/vininhosts/CommandNest/main/Scripts/install-linux.sh | bash
```

Install on Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/vininhosts/CommandNest/main/Scripts/install-windows.ps1 | iex
```

Run it locally:

```sh
cd CrossPlatform
npm ci
npm start
```

Package target builds:

```sh
cd CrossPlatform
npm run package:windows
npm run package:linux
```

GitHub Actions builds Windows bundles on Windows runners and Linux bundles on Ubuntu runners. Those archives are uploaded to tagged releases.

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
HTTP-Referer: https://github.com/vininhosts/CommandNest
X-Title: CommandNest
```

Default models start with the free router:

- `openrouter/free`

CommandNest also loads the current OpenRouter model catalog from:

```text
https://openrouter.ai/api/v1/models
```

The Settings window has a `Load All` button to refresh the editable model list. On launch, the app also refreshes the model list in the background. Model pickers are searchable, so large OpenRouter model lists do not require scrolling from the top.

Bundled fallback models:

- `openai/gpt-4o-mini`
- `anthropic/claude-3.5-haiku`
- `google/gemini-flash-1.5`
- `meta-llama/llama-3.1-8b-instruct`

## Local Agent Mode

Settings includes `Enable local agent mode`, which is on by default for agent-like behavior. Normal chat still streams. CommandNest switches to local agent mode only when the prompt looks like a file, folder, app, code, shell, browser, email, GitHub, MCP, or computer action.

Settings also includes `Ask before high-impact agent actions`, which is on by default. Read-only directory listing, text-file reading, file search, text search, git status, and git diff can proceed without a prompt; writes, moves, Trash, shell commands, browser control, email actions, GitHub uploads, external MCP calls, and native file organization show a confirmation dialog first.

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
- Search files and grep project text
- Replace text in files
- Infer and run common project test commands
- Check git status and diffs
- Commit, push, create GitHub pull requests, and create GitHub releases through the `gh` CLI
- Navigate Safari/Chrome, read front-tab text, execute front-tab JavaScript, and open web searches
- Compose email drafts or send through Apple Mail after confirmation
- List and call tools on configured MCP stdio servers

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

The assistant window keeps a compact activity log for local agent actions so users can see what was requested, approved, skipped, and run.

Useful permissions:

- Full Disk Access: needed for broad file access, including protected folders.
- Accessibility and Automation: needed for AppleScript browser and Mail control.
- Screen Recording: needed for future screen-aware workflows.

CommandNest cannot grant these permissions to itself. Use the buttons in Settings to open the correct System Settings panes, then enable CommandNest.

## MCP Integrations

CommandNest includes a generic MCP stdio bridge. The agent can list configured MCP servers, list server tools, and call MCP tools with user confirmation. Built-in presets are included for:

- `filesystem`: `npx -y @modelcontextprotocol/server-filesystem <home>`
- `github`: `npx -y @modelcontextprotocol/server-github`
- `browser`: `npx -y @playwright/mcp@latest`

You can add or override MCP servers in either `~/.commandnest/mcp.json` or the app support `mcp.json` file. Use the common Claude-style format:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "npx",
      "args": ["-y", "some-mcp-server"],
      "env": {
        "TOKEN": "value"
      }
    }
  }
}
```

External MCP tools can do powerful things. CommandNest treats `mcp_call_tool` as high impact and asks before running it.

## Updates

Use the menu bar item `Check for Updates...` to compare the installed version with the latest GitHub Release. This opens the release page when a newer build is available. Full automatic installation is intentionally left for a future Sparkle integration once signing and notarization are configured.

## Launch at Login

Enable `Launch CommandNest at login` in Settings to register the app with macOS Login Items using `SMAppService`. macOS may show CommandNest in System Settings under `General > Login Items & Extensions`.

## Tests

```sh
xcodebuild -project CommandNest.xcodeproj -scheme CommandNest -configuration Debug -destination 'platform=macOS' test
```

The current test target covers settings migrations, model normalization, local file creation, folder organization, manifest writing, conflict-safe moves, skipped incomplete downloads, undoing organization from a manifest, agent safety checks, update comparisons, and reasoning/thinking parsing.

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
│   ├── PermissionService.swift
│   ├── UpdateService.swift
│   └── LaunchAtLoginService.swift
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
    ├── Constants.swift
    └── ReasoningTextParser.swift
CommandNestTests/
├── AppSettingsTests.swift
└── LocalActionServiceTests.swift
CrossPlatform/
├── package.json
├── src/main.js
├── src/preload.js
└── src/renderer/
```

## Info.plist and Entitlements

`Info.plist` sets `LSUIElement` to `true`, so CommandNest runs as a menu bar app without a Dock icon. The production bundle identifier is `io.github.vininhosts.CommandNest`. The included entitlements file is intentionally empty because the app is not sandboxed by default. If you enable App Sandbox later, add the outbound network client entitlement and revisit local agent capabilities.
