# Distribution

CommandNest can be distributed as a zipped macOS `.app` bundle so users do not need Xcode. The repository also includes an Electron edition for Windows and Linux under `CrossPlatform/`.

## Local Packaging

```sh
Scripts/package_release.sh
```

The script creates:

```text
dist/CommandNest-<version>-<build>.zip
dist/CommandNest-<version>-<build>.sha256
```

Without a `CODESIGN_IDENTITY`, the script applies an ad-hoc signature. This is enough for local testing, but macOS Gatekeeper may show a warning for downloaded builds.

## Developer ID Signing

For a smoother public download, build with a Developer ID Application certificate:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/package_release.sh
```

Then notarize the zip with Apple:

```sh
xcrun notarytool submit dist/CommandNest-<version>-<build>.zip \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait
```

After notarization succeeds, staple the ticket to the app before zipping if you are distributing the raw `.app`, or distribute the notarized zip as the GitHub release asset.

## GitHub Release

Tag a release:

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```

The `Release` workflow builds the zip and attaches it to a GitHub Release.

The same workflow also packages:

```text
CommandNest-win32-x64.zip
CommandNest-win32-arm64.zip
CommandNest-linux-x64.tar.gz
CommandNest-linux-arm64.tar.gz
```

Windows/Linux bundles are not code signed yet. Add platform signing credentials before presenting them as fully trusted production downloads.
