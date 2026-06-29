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

## Beta Preview

Fort Aidar is currently a beta/partner preview, not a production notarized
release.

You can download the current preview build from:

<https://github.com/AI-Venture-Engine/FortAidar/releases/tag/v0.1.0-preview>

This preview app is ad-hoc signed, but it is not signed with Apple Developer ID
and is not notarized yet. On another Mac, Gatekeeper may warn that the app is
from an unidentified developer. That is expected for this beta build; users may
need to approve the first launch manually in macOS.

The local packaging script now produces both a `.zip` package and a preview
`.dmg`. The DMG is easier for partners to open and inspect, but it is still
only a preview artifact until Developer ID signing and notarization are in
place.

Before a wider public release, the intended distribution steps are:

1. Apple Developer ID registration.
2. Hardened Runtime configuration.
3. Developer ID signing.
4. Apple notarization.
5. A notarized `.dmg` installer.
6. A short onboarding guide for partner and public testers.

For now, treat this build as a test vault preview. Do not store the only copy of
important documents in it.

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
- `AutoLockPolicy`: shared idle-deadline logic for short mount windows.
- `SessionTokenIssuer`: short-lived HMAC-backed agent session tokens.
- `AuditEvent` and `AuditEventCodec`: machine-readable local audit events.

It also contains a first SwiftUI prototype app:

- one-window macOS interface
- simple local `Sign in` / `Register` flow keyed by email
- `Register` starts with an empty email field so a second local user can create
  a separate vault without seeing the previous user's address
- email normalization for common Cyrillic/Latin lookalike letters before vault
  lookup
- create/unlock an encrypted sparsebundle with a password
- save the vault password in Keychain protected by biometric access control
- unlock later with Touch ID when the Mac supports it
- drag files or folders into the unlocked vault
- add files or folders with the `Add` button
- lock/detach the vault
- auto-lock the mounted vault after 10 minutes of idle time
- reveal the sparsebundle or current mounted vault
- activity panel and local JSONL audit log
- VaultDog embedded guardian scene

The `fortaidar` executable is a minimal MCP-compatible stdio server for the
preview. It supports `initialize`, `tools/list`, `tools/call`, and a read-only
`fortaidar.status` tool. Unlocking and file import are still intentionally
human-controlled in the macOS app.

Email is a local vault selector in this preview, not a cloud account. There is
no email recovery flow yet: if a user forgets the vault password and it was not
successfully saved in Keychain, the vault contents cannot be recovered through
Fort Aidar.

Touch ID support is intentionally simple in this prototype: after a successful
password registration/sign-in, Fort Aidar tries to store the vault password in
Keychain with biometric access control and `ThisDeviceOnly`. If the preview
build lacks the entitlements needed for biometric Keychain items, it falls back
to a `ThisDeviceOnly` Keychain item and requires Touch ID through
LocalAuthentication before reading it. First-time registration uses a password;
Touch ID is deliberately a follow-up convenience path in this preview.

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

Email-based local users use isolated vault paths under:

```text
~/FortAidar/Vaults/
```

Usage:

1. Choose `Register` for a first local user, enter an email, and enter a
   password twice. The email field is intentionally blank in Register mode.
2. The vault opens immediately after successful registration.
3. On later runs, choose `Sign in`, enter the same email, and use the password
   or `Touch ID` when available.
4. Click `Add` or drop files/folders into the VaultDog drop zone.
5. Click `Lock` when finished, or let auto-lock detach after 10 minutes idle.

## MCP / Agent Smoke Test

The preview server currently exposes read-only redacted status:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"fortaidar.status"}' | swift run fortaidar
```

Minimal MCP tool flow:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fortaidar.status","arguments":{}}}' \
  | swift run fortaidar
```

## Partner Preview Package

For early partner handoff, build and package the app from a local checkout:

```sh
./script/package_preview.sh
```

The package is written under `release/`. It includes the staged `.app`,
preview notes, security notes, `BUILD_INFO.txt`, a `.zip`, a `.dmg`, and
SHA-256 checksum files. The app window and DMG volume include the build stamp so
parallel preview builds can be distinguished. Until Developer ID signing and
notarization are configured, macOS may warn that the app is from an unidentified
developer even when partners use the DMG.

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
- Expand MCP server from read-only status to reviewed agent access flows.
- Pocket Mode and Fort Artifact companion interactions.
- Developer ID signing, hardened runtime, and notarization.
