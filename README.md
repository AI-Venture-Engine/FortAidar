# Fort Aidar

Fort Aidar is a free macOS-first protected vault preview for people, models,
and agents.

The first implementation deliberately relies on Apple system mechanisms instead
of custom cryptography:

- encrypted sparsebundle/DMG via `hdiutil`
- Keychain and LocalAuthentication for human unlock
- application-level agent grants through a local MCP/JSON-RPC facade
- audit-first access model

The app also experiments with a more playful security interface: VaultDog acts
as a visible guardian for the vault while the actual protection stays grounded
in Apple platform primitives.

## Security framing

Agent grants are application-level policy, not OS-level sandboxing. When the
vault is mounted, its contents are plaintext to processes running as the same
macOS user. Fort Aidar reduces exposure by keeping the vault unmounted by
default, using short mount windows, hiding the real mountpoint from agents, and
requiring human confirmation for risky operations.

Read [SECURITY_NOTES.md](SECURITY_NOTES.md) before using the preview with
important documents.

## Current MVP slice

This package currently contains a testable Swift core skeleton:

- `LogicalPathPolicy`: maps agent logical paths into scoped namespaces.
- `HdiutilCommand`: builds safe `hdiutil` attach/detach commands without putting
  passphrases in process arguments.
- `FortMethod` and `FortStatus`: typed JSON-RPC/MCP contract primitives.
- `SessionTokenIssuer`: short-lived HMAC-backed agent session tokens.
- `AuditEvent`: required audit fields for future SQLite persistence.

It also contains a first SwiftUI prototype app:

- one-window macOS interface
- identity selector for a local human profile and model/agent profiles
- create/unlock encrypted sparsebundle with a passphrase
- save the vault passphrase in Keychain protected by biometric access control
- unlock later with Touch ID when the Mac supports it
- drag files or folders into the unlocked vault
- add files or folders with the `Add` button
- lock/detach the vault
- reveal the sparsebundle or current mounted vault
- activity panel for the first human-readable event trail
- VaultDog embedded guardian scene

Touch ID support is intentionally simple in this prototype: after a successful
passphrase create/unlock, Fort Aidar stores the vault passphrase in Keychain
with `biometryCurrentSet` and `ThisDeviceOnly`. Later unlocks can ask Keychain
to release that secret through biometric authentication. The passphrase fallback
remains available.

## Run From Source

```sh
./script/build_and_run.sh
```

The run script stages the development app at:

```text
~/Applications/Fort Aidar.app
```

The prototype stores the encrypted sparsebundle at:

```text
~/FortAidar/FortAidar.sparsebundle
```

Additional model/agent identities use isolated vault paths under:

```text
~/FortAidar/Vaults/
```

Usage:

1. Select an identity.
2. Enter a passphrase.
3. Click `Create` or `Unlock`.
4. On later runs, click `Touch ID` if available.
5. Click `Add` or drop files/folders into the VaultDog drop zone.
6. Click `Lock` when finished.

## Partner Preview Package

For early partner handoff, build and package the app from a local checkout:

```sh
./script/package_preview.sh
```

The package is written under `release/`. It includes the staged `.app`,
preview notes, and security notes. Until Developer ID signing and notarization
are configured, macOS may warn that the app is from an unidentified developer.

## Verification

The local Swift toolchain in this environment does not expose `Testing` or
`XCTest`, so the first specs are implemented as an executable runner:

```sh
swift run fortaidar-core-spec
swift build
./script/build_and_run.sh --verify
```

`swift test` is intentionally not the active verification command until the
toolchain test modules are available again.

## Roadmap Direction

- Google Workspace / OIDC sign-in for human identity.
- MCP server packaging for model/agent access.
- Pocket Mode and Fort Artifact companion interactions.
- Developer ID signing, hardened runtime, and notarization.
