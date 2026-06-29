# Fort Aidar Partner Preview

Fort Aidar is a free, AI-native protected vault for people and agents. This
preview focuses on a local macOS vault with a simple, visible workflow:

1. Register a local user with email plus password.
2. Sign in later with email plus password or Touch ID.
3. Add files or folders.
4. Lock the vault when finished.

In this preview, email is only a local vault selector on this Mac. It is not a
cloud account and does not provide email-based recovery. Register mode starts
with a blank email field so another person can create a separate local vault.

## Current Features

- macOS SwiftUI preview app.
- Local encrypted sparsebundle storage.
- Keychain + Touch ID unlock after password registration or sign-in.
- Email-keyed local vault separation.
- Drag and drop import.
- Add button import.
- 10 minute idle auto-lock after unlock.
- Activity panel.
- Local JSONL audit log.
- VaultDog visual guardian scene.
- Core policy/spec runner for agent-path, token, audit, and auto-lock
  primitives.
- Minimal MCP-compatible stdio server with read-only `fortaidar.status`.

## Known Preview Gaps

- No Developer ID notarization yet.
- Preview DMG is available for handoff, but it is not notarized yet.
- No Google Workspace sign-in yet.
- No cloud recovery.
- No email password reset flow yet; keep the vault password safe.
- MCP is read-only status only; no production agent file access yet.
- No automatic updater.
- Current character animation is an embedded preview, not the final Pocket Mode.

## Verification Commands

```sh
swift run fortaidar-core-spec
swift build --product fortaidar
swift build --product FortAidarApp
./script/build_and_run.sh --verify
```
