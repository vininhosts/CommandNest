# CommandNest 1.1.0

Production-readiness release with safer local agent behavior and a stable app identity.

CommandNest is a native macOS menu bar AI assistant with a global `Option + Space` command palette, OpenRouter streaming responses, secure Keychain API key storage, and local agent actions for files, folders, shell commands, and app/URL opening.

## Download

Download `CommandNest-1.1.0-3.zip`, unzip it, move `CommandNest.app` to `/Applications`, then open it from Finder.

## Highlights

- Stable bundle ID: `io.github.vininhosts.CommandNest`.
- Public OpenRouter referer: `https://github.com/vininhosts/CommandNest`.
- First-launch onboarding.
- Menu bar update checker for GitHub Releases.
- Confirmation prompts for local writes, moves, Trash, app/URL opens, shell commands, and native file organization.
- Compact local-agent activity log in the assistant window.

This first release is ad-hoc signed unless a maintainer builds it with a Developer ID certificate. macOS may require right-clicking the app and choosing `Open` the first time.

## Permissions

The global hotkey normally needs no Accessibility permission. macOS may ask for Desktop, Documents, Downloads, external drive, network volume, or Full Disk Access permission when you ask CommandNest to inspect or organize protected locations.
