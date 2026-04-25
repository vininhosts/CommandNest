## Summary

Describe the user-visible change.

## Testing

- [ ] `xcodebuild -project CommandNest.xcodeproj -scheme CommandNest -configuration Debug -destination 'platform=macOS' test`
- [ ] Manual app launch

## Agent Safety

- [ ] This change does not alter local file, shell, or app-opening behavior.
- [ ] If it does, destructive or privileged actions are visible to the user and covered by tests.

