# CommandNest 1.2.0

UI polish and cross-platform expansion release.

## Download

macOS: download `CommandNest-1.2.0-4.zip`, unzip it, move `CommandNest.app` to `/Applications`, then open it from Finder.

Windows/Linux: download the matching `CommandNest-win32-*.zip` or `CommandNest-linux-*.tar.gz` asset from this release.

## Highlights

- Markdown rendering for assistant responses, so `**bold**` and code formatting render cleanly.
- Collapsible Thinking panel for provider reasoning and `<think>...</think>` output, keeping the final answer clean.
- Searchable model picker in both the assistant window and Settings.
- Windows/Linux Electron edition with tray menu, global `Alt+Space`, OpenRouter streaming, secure API key storage, launch at login, and local agent tools.
- GitHub Actions packaging for Windows and Linux release assets.
- Additional tests for reasoning/thinking parsing.

macOS release builds are ad-hoc signed unless a maintainer builds them with a Developer ID certificate. Windows/Linux bundles are not code signed yet.

## Permissions

The global hotkey normally needs no Accessibility permission. Local agent actions can only access files and shell capabilities available to your OS user, and write/shell/open actions show confirmation prompts when enabled.
