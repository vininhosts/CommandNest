# CommandNest 1.2.0

UI polish and cross-platform expansion release.

## Download

macOS: download `CommandNest-macOS.zip`, unzip it, move `CommandNest.app` to `/Applications`, then open it from Finder. The versioned `CommandNest-1.2.0-4.zip` asset is also included for archival installs.

Windows/Linux: download the matching `CommandNest-win32-*.zip` or `CommandNest-linux-*.tar.gz` asset from this release.

Matching `.sha256` files are available for all release archives.

Quick install scripts are available from the repository:

```sh
curl -fsSL https://raw.githubusercontent.com/vininhosts/CommandNest/main/Scripts/install-macos.sh | bash
curl -fsSL https://raw.githubusercontent.com/vininhosts/CommandNest/main/Scripts/install-linux.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/vininhosts/CommandNest/main/Scripts/install-windows.ps1 | iex
```

## Highlights

- Markdown rendering for assistant responses, so `**bold**` and code formatting render cleanly.
- Collapsible Thinking panel for provider reasoning and `<think>...</think>` output, keeping the final answer clean.
- Searchable model picker in both the assistant window and Settings.
- Windows/Linux Electron edition with tray menu, global `Alt+Space`, OpenRouter streaming, secure API key storage, launch at login, and local agent tools.
- Expanded agent tools for code search/editing, project test runs, git/GitHub publishing, browser actions, email, and MCP stdio integrations.
- GitHub Actions packaging for Windows and Linux release assets.
- Additional tests for reasoning/thinking parsing.

macOS release builds are ad-hoc signed unless a maintainer builds them with a Developer ID certificate. Windows/Linux bundles are not code signed yet.

## Permissions

The global hotkey normally needs no Accessibility permission. Local agent actions can only access files and shell capabilities available to your OS user, and write/shell/open/browser/email/GitHub/MCP actions show confirmation prompts when enabled.
