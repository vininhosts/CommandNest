# CommandNest Cross-Platform

This is the Windows and Linux edition of CommandNest. It uses Electron so the global shortcut, tray menu, floating palette, OpenRouter streaming, searchable model picker, and local agent tools can run outside macOS.

## Features

- Global shortcut, default `Alt+Space`
- Tray menu with Show Assistant, Settings, Launch at Login, and Quit
- Floating command palette with streamed OpenRouter responses
- Searchable model picker
- Markdown response rendering
- Separate collapsible Thinking panel for model reasoning or `<think>...</think>` output
- Secure API key storage through Electron `safeStorage`
- Local agent mode with file, folder, shell, and open-item tools
- Windows and Linux packaging through GitHub Actions

## Run Locally

```sh
cd CrossPlatform
npm ci
npm start
```

## Package

```sh
cd CrossPlatform
npm run package:windows
npm run package:linux
```

Packaging should be run on the target OS for best results. The GitHub workflow builds Windows bundles on Windows runners and Linux bundles on Ubuntu runners.

## API Key

Open Settings, paste your OpenRouter API key, and save. The key is encrypted with the operating system secure storage when available. For development only, you can also launch with `OPENROUTER_API_KEY` set in the environment.

## Permissions

The app can only access paths and shell capabilities the current OS user can access. Agent write, shell, open, move, copy, and trash actions show a confirmation prompt when confirmation is enabled.
