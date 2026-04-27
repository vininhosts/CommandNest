# CommandNest 1.3.2

Gmail MCP routing release.

## Download

macOS: download `CommandNest-macOS.zip`, unzip it, move `CommandNest.app` to `/Applications`, then open it from Finder. The versioned `CommandNest-1.3.2-7.zip` asset is also included for archival installs.

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

- Added `gmail_send_email`, a high-impact confirmed agent tool that sends through a configured Gmail MCP server.
- Updated the native macOS app and Windows/Linux Electron edition so Gmail prompts prefer Gmail MCP over Apple Mail or mailto drafts.
- Added Gmail MCP setup documentation using a `gmail` server in `~/.commandnest/mcp.json`.
- Kept Apple Mail/default mail draft behavior for non-Gmail email requests.

macOS release builds are ad-hoc signed unless a maintainer builds them with a Developer ID certificate. Windows/Linux bundles are not code signed yet.

## Permissions

The global hotkey normally needs no Accessibility permission. Local agent actions can only access files and shell capabilities available to your OS user, and write/shell/open/browser/email/GitHub/MCP actions show confirmation prompts when enabled.
