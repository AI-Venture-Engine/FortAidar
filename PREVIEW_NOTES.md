# Fort Aidar Partner Preview

Fort Aidar is a free, AI-native protected vault for people and agents. This
preview focuses on a local macOS vault with a simple, visible workflow:

1. Select an identity.
2. Create or unlock a local encrypted vault.
3. Add files or folders.
4. Lock the vault when finished.

## Current Features

- macOS SwiftUI preview app.
- Local encrypted sparsebundle storage.
- Keychain + Touch ID unlock after first manual unlock.
- Identity selector for human/model vault separation.
- Drag and drop import.
- Add button import.
- Activity panel.
- VaultDog visual guardian scene.
- Core policy/spec runner for agent-path, token, and audit primitives.

## Known Preview Gaps

- No Developer ID notarization yet.
- No Google Workspace sign-in yet.
- No cloud recovery.
- No production MCP server shipped in the preview bundle yet.
- No automatic updater.
- Current character animation is an embedded preview, not the final Pocket Mode.

## Verification Commands

```sh
swift run fortaidar-core-spec
swift build --product FortAidarApp
./script/build_and_run.sh --verify
```

