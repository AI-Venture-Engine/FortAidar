# Fort Aidar Security Notes

Fort Aidar is a pre-production macOS preview. It is intended for trusted early
partners who understand the current limitations.

## What Is Protected

- Fort Aidar creates an Apple encrypted sparsebundle using `hdiutil`.
- The vault is mounted only while the user is working with it.
- The passphrase is sent to `hdiutil` through standard input, not as a process
  argument.
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

## Partner Guidance

- Use a test vault first.
- Do not store the only copy of important documents in the preview.
- Lock the vault when finished.
- Keep a separate backup of critical files until the app is signed, notarized,
  and reviewed for production use.

