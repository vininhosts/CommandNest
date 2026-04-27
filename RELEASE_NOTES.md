# CommandNest 1.3.1

Windows reliability release.

## Download

macOS: download `CommandNest-macOS.zip`, unzip it, move `CommandNest.app` to `/Applications`, then open it from Finder. The versioned `CommandNest-1.3.1-6.zip` asset is also included for archival installs.

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

- Reworked the Windows edition around native Windows behavior instead of Mac-style menu-bar assumptions.
- Changed the Windows default global shortcut to `Ctrl+Shift+Space`; existing Windows installs that still have `Alt+Space` saved are migrated automatically.
- Kept the Windows window visible in the taskbar and stopped auto-hiding it on blur, so Settings and the assistant no longer feel like they disappear.
- Improved the Windows installer by stopping old running copies, creating Start menu and desktop shortcuts, launching the installed app, and printing the active shortcut.
- Fixed Windows MCP startup for `npm`/`npx` based servers and replaced fragile `findstr` text search with a built-in Node search path.

macOS release builds are ad-hoc signed unless a maintainer builds them with a Developer ID certificate. Windows/Linux bundles are not code signed yet.

## Permissions

The global hotkey normally needs no Accessibility permission. Local agent actions can only access files and shell capabilities available to your OS user, and write/shell/open/browser/email/GitHub/MCP actions show confirmation prompts when enabled.
