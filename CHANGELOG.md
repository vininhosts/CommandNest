# Changelog

## 1.1.0

- Switched the app and test bundle identifiers to `io.github.vininhosts.CommandNest`.
- Updated the OpenRouter `HTTP-Referer` header to the public GitHub repository.
- Added first-launch onboarding and a menu bar update checker for GitHub Releases.
- Added confirmation prompts and activity logging for local agent file, app, and shell actions.
- Added tests for action confirmation, shell-command safety, and version comparison.

## 1.0.1

- Added macOS privacy usage descriptions for Desktop, Documents, Downloads, removable volume, and network volume access.
- Updated GitHub Actions checkout usage for current hosted runners.

## 1.0.0

- Initial open-source release of CommandNest.
- Native macOS menu bar assistant with global `Option + Space` hotkey.
- OpenRouter streaming chat completions with non-streaming fallback.
- Secure OpenRouter API key storage in macOS Keychain.
- Free Models Router default model: `openrouter/free`.
- Local Agent Mode for file, shell, and open-item tools.
- Native local actions for organizing folders, undoing organization, and creating text files.
- XCTest coverage for settings migrations and local file actions.
