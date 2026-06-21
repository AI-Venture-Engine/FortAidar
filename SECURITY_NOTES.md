# Fort Aidar Security Notes

Fort Aidar is a pre-production macOS preview. It is intended for trusted early
partners who understand the current limitations.

## What Is Protected

- Fort Aidar creates an Apple encrypted sparsebundle using `hdiutil`.
- The vault is mounted only while the user is working with it.
- The preview app auto-locks the mounted vault after 10 minutes of idle time.
- The passphrase is sent to `hdiutil` through standard input, not as a process
  argument.
- The mounted sparsebundle uses `stdinpass`, `nobrowse`, and `noautoopen`
  attach flags. macOS may add mount protections such as `nodev`, `nosuid`, and
  `noowners`; unsupported `hdiutil attach` flags are not passed.
- After a successful manual unlock, Fort Aidar can store the vault passphrase in
  Keychain with biometric access control.
- Touch ID unlock asks Keychain to release the stored vault secret for the
  selected identity.

## Important Limits

- This preview is not notarized yet.
- This preview does not provide cloud recovery.
- If a passphrase is lost and it was not saved in Keychain, the local vault
  cannot be reset without losing access to its contents.
- When the vault is mounted, files are visible as plaintext to processes running
  as the same macOS user.
- Current agent/MCP access control is an application-level design direction, not
  an OS sandbox boundary.
- The current MCP-compatible server exposes read-only redacted status only. It
  does not grant agent file access in this preview.

## Preview Audit Log

- Fort Aidar writes a local activity log to
  `~/Library/Application Support/FortAidar/audit/events.jsonl`
  (one JSON line per event).
- It records app-side events such as vault create, unlock, lock, identity
  switch, file import, and Touch ID / Keychain outcomes.
- Events use machine-readable keys (operation, outcome, requester, logical
  target, mount state, session id). No passphrase or vault secret is ever
  written to this log.
- The log lives outside the encrypted vault and outside any agent logical
  namespace.
- What it does NOT guarantee yet: it is append-only on a best-effort basis but
  is not tamper-evident (no hash chaining) and is not yet written by an MCP
  server. A process running as the same macOS user can read or alter the file.
  Treat it as a local activity record for this preview, not a forensic audit.

## Partner Guidance

- Use a test vault first.
- Do not store the only copy of important documents in the preview.
- Lock the vault when finished.
- Keep a separate backup of critical files until the app is signed, notarized,
  and reviewed for production use.
