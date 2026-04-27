# CommandNest 1.3.0

Agent expansion release.

## Download

macOS: download `CommandNest-macOS.zip`, unzip it, move `CommandNest.app` to `/Applications`, then open it from Finder. The versioned `CommandNest-1.3.0-5.zip` asset is also included for archival installs.

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

- Expanded native macOS agent tools for code search/editing, project test runs, git/GitHub publishing, browser actions, email, and MCP stdio integrations.
- Expanded Windows/Linux agent tools for code editing, test runs, git/GitHub publishing, browser/search actions, email drafts, and MCP stdio integrations.
- Added built-in MCP presets for filesystem, GitHub, and Playwright browser servers, plus user-configurable `mcp.json` support.
- Added safety coverage requiring confirmation for browser page reads/control, email sending, GitHub publishing, and external MCP tool calls.
- Updated documentation, privacy notes, security guidance, and landing page copy for the expanded agent capabilities.

macOS release builds are ad-hoc signed unless a maintainer builds them with a Developer ID certificate. Windows/Linux bundles are not code signed yet.

## Permissions

The global hotkey normally needs no Accessibility permission. Local agent actions can only access files and shell capabilities available to your OS user, and write/shell/open/browser/email/GitHub/MCP actions show confirmation prompts when enabled.
