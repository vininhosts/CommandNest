# Contributing to CommandNest

Thanks for helping make CommandNest better.

## Local Setup

1. Install Xcode 15 or newer.
2. Open `CommandNest.xcodeproj`.
3. Select the `CommandNest` scheme.
4. Build and test on macOS 14 or newer.

Terminal build:

```sh
xcodebuild -project CommandNest.xcodeproj -scheme CommandNest -configuration Debug -destination 'platform=macOS' build
```

Terminal tests:

```sh
xcodebuild -project CommandNest.xcodeproj -scheme CommandNest -configuration Debug -destination 'platform=macOS' test
```

## Pull Requests

- Keep changes focused and explain user-visible behavior.
- Add XCTest coverage for local actions, settings migrations, parsing, or network request behavior when practical.
- Do not commit API keys, screenshots containing secrets, DerivedData, or personal Xcode state.
- Be careful with agent tools. Any change that can read, write, move, delete, or execute local content should include error handling and a clear user-facing result.
