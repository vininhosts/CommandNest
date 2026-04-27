# Changelog

## 1.3.1

- Reworked Windows defaults so the Electron app uses `Ctrl+Shift+Space` instead of the OS-reserved `Alt+Space`.
- Kept the Windows assistant visible in the taskbar and stopped hiding it automatically on blur.
- Improved Windows installer shortcuts and relaunch behavior.
- Fixed Windows MCP startup for npm/npx-based servers and made text search avoid fragile `findstr` shell quoting.

## 1.3.0

- Expanded local agent tools for coding workflows, project tests, git/GitHub publishing, browser actions, email, and MCP stdio integrations.
- Added safety coverage requiring confirmation for browser page reads/control, email sending, GitHub publishing, and MCP tool calls.
- Updated Windows/Linux agent capabilities to match the expanded native macOS agent surface.

## 1.2.0

- Added Markdown rendering for assistant responses to avoid raw formatting markers in chat.
- Separated model reasoning and `<think>...</think>` output into a collapsible Thinking panel.
- Added searchable model pickers in the assistant window and Settings.
- Added an Electron-based Windows/Linux edition under `CrossPlatform/`.
- Added GitHub Actions packaging for Windows and Linux release bundles.
- Added stable latest release asset names, installer scripts, and a GitHub Pages landing page.
- Added tests for reasoning/thinking parsing.

## 1.1.0

- Switched the app and test bundle identifiers to `io.github.vininhosts.CommandNest`.
- Updated the OpenRouter `HTTP-Referer` header to the public GitHub repository.
- Added first-launch onboarding and a menu bar update checker for GitHub Releases.
- Added a Settings toggle to launch CommandNest automatically at login.
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
