import AppKit
import Foundation
import FortAidarCore
import SwiftUI

@MainActor
final class PrototypeVaultStore: ObservableObject {
    @Published var identities: [VaultIdentity] = [
        VaultIdentity(id: "default", displayName: "Aidar local", handle: "aidar", kind: .person),
        VaultIdentity(id: "model-kimi", displayName: "Kimi", handle: "kimi", kind: .agent),
        VaultIdentity(id: "model-lu2", displayName: "Lu2", handle: "lu2", kind: .agent),
        VaultIdentity(id: "model-ag", displayName: "Antigravity", handle: "ag", kind: .agent)
    ]
    @Published var selectedIdentityID = "default"
    @Published var state: VaultState = .working("Checking vault")
    @Published var items: [VaultItem] = []
    @Published var events: [VaultEvent] = []
    @Published var isDropTargeted = false
    @Published var passphrase = ""
    @Published var passphraseConfirmation = ""
    @Published var isPassphraseVisible = false
    @Published var passphraseFieldToken = UUID()
    @Published var canUnlockWithBiometrics = false
    @Published var biometricStatusText = "Touch ID setup pending"
    let vaultDogBridge = VaultDogBridge()

    private let keychain = BiometricVaultSecretStore()
    private var mountPoint: URL?

    var selectedIdentity: VaultIdentity {
        identities.first { $0.id == selectedIdentityID } ?? identities[0]
    }

    private var runtime: PrototypeVaultRuntime {
        PrototypeVaultRuntime(identity: selectedIdentity)
    }

    var vaultPathText: String {
        runtime.vaultPath.path
    }

    var stateSymbolName: String {
        switch state {
        case .missing:
            return "plus.square.dashed"
        case .locked:
            return "lock.fill"
        case .unlocked:
            return "lock.open.fill"
        case .working:
            return "hourglass"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var stateTint: Color {
        switch state {
        case .missing:
            return .secondary
        case .locked:
            return .gray
        case .unlocked:
            return .green
        case .working:
            return .blue
        case .error:
            return .orange
        }
    }

    var isCreatingNewVault: Bool {
        !runtime.vaultExists()
    }

    var selectedIdentityKindText: String {
        switch selectedIdentity.kind {
        case .person:
            return "person"
        case .agent:
            return "model"
        }
    }

    func refresh() async {
        canUnlockWithBiometrics = keychain.hasStoredSecret(for: selectedIdentity)
        biometricStatusText = keychain.canEvaluateBiometrics()
            ? (canUnlockWithBiometrics ? "Touch ID ready for \(selectedIdentity.displayName)" : "Touch ID will be saved after first unlock for \(selectedIdentity.displayName)")
            : "Touch ID is not available on this Mac"

        if let mountPoint {
            items = runtime.listItems(at: mountPoint)
            state = .unlocked(mountPoint: mountPoint)
        } else if runtime.vaultExists() {
            state = .locked
        } else {
            state = .missing
        }
    }

    func selectIdentity(_ identityID: String) {
        guard identityID != selectedIdentityID else { return }
        selectedIdentityID = identityID
        passphrase = ""
        passphraseConfirmation = ""
        mountPoint = nil
        items = []
        appendEvent("Identity selected", "\(selectedIdentity.displayName) (\(selectedIdentityKindText))")

        Task { await refresh() }
    }

    func focusPassphraseField() {
        passphraseFieldToken = UUID()
    }

    func createOrUnlock() async {
        guard !passphrase.isEmpty else {
            appendEvent("Passphrase required", "Enter a passphrase to create or unlock the vault.")
            return
        }

        if isCreatingNewVault {
            guard !passphraseConfirmation.isEmpty else {
                appendEvent("Confirm passphrase", "Enter the same passphrase twice before creating a new vault.")
                return
            }

            guard passphrase == passphraseConfirmation else {
                appendEvent("Passphrases do not match", "Check the visible text or keyboard layout, then try again.")
                return
            }
        }

        await createOrUnlock(passphrase: passphrase, shouldSaveSecret: true)
    }

    func performPrimaryVaultAction() async {
        if state.isMounted {
            await lock()
        } else {
            await createOrUnlock()
        }
    }

    func unlockWithBiometrics() async {
        do {
            state = .working("Authenticating")
            let secret = try keychain.readPassphrase(for: selectedIdentity)
            appendEvent("Authenticated", "Keychain released the vault secret for \(selectedIdentity.displayName).")
            await createOrUnlock(passphrase: secret, shouldSaveSecret: false)
        } catch {
            state = runtime.vaultExists() ? .locked : .missing
            appendEvent("Touch ID failed", error.localizedDescription)
        }
    }

    func addItemsWithPicker() {
        guard state.isMounted, let mountPoint else {
            appendEvent("Add blocked", "Unlock the vault first.")
            focusPassphraseField()
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Add to Fort Aidar"
        panel.prompt = "Add"
        panel.message = "Choose files or folders to copy into the encrypted vault."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        let response = panel.runModal()
        guard response == .OK else {
            return
        }

        importFileURLs(panel.urls, into: mountPoint)
    }

    private func createOrUnlock(passphrase: String, shouldSaveSecret: Bool) async {
        let enteredPassphrase = passphrase

        do {
            if !runtime.vaultExists() {
                state = .working("Creating encrypted vault")
                appendEvent("Creating vault", "Building encrypted sparsebundle for \(selectedIdentity.displayName).")
                try await runtime.createVault(passphrase: enteredPassphrase)
                appendEvent("Vault created", runtime.vaultPath.path)
            }

            state = .working("Unlocking vault")
            let mountedAt = try await runtime.unlock(passphrase: enteredPassphrase)
            self.passphrase = ""
            self.passphraseConfirmation = ""
            mountPoint = mountedAt
            items = runtime.listItems(at: mountedAt)
            state = .unlocked(mountPoint: mountedAt)
            appendEvent("Unlocked", "\(selectedIdentity.displayName) vault mounted for this session.")

            if shouldSaveSecret {
                saveSecretForBiometrics(enteredPassphrase)
            }
        } catch {
            let message = friendlyUnlockError(from: error)
            state = .error(message)
            appendEvent("Unlock failed", message)
        }
    }

    func lock() async {
        guard let mountPoint else {
            await refresh()
            return
        }

        do {
            state = .working("Locking vault")
            try await runtime.lock(mountPoint: mountPoint)
            self.mountPoint = nil
            items = []
            state = .locked
            appendEvent("Locked", "\(selectedIdentity.displayName) vault detached.")
        } catch {
            state = .error(error.localizedDescription)
            appendEvent("Lock failed", error.localizedDescription)
        }
    }

    func importProviders(_ providers: [NSItemProvider]) -> Bool {
        guard state.isMounted, let mountPoint else {
            appendEvent("Drop ignored", "Unlock the vault first.")
            return false
        }

        let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(fileURLType) }
        guard !matching.isEmpty else {
            appendEvent("Drop ignored", "Only files and folders are supported.")
            return false
        }

        for provider in matching {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { [weak self] item, error in
                let droppedURL: URL?
                if let data = item as? Data {
                    droppedURL = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    droppedURL = url
                } else {
                    droppedURL = nil
                }

                let errorDescription = error?.localizedDescription

                Task { @MainActor in
                    guard let self else { return }
                    if let errorDescription {
                        self.appendEvent("Import failed", errorDescription)
                        return
                    }

                    guard let url = droppedURL else {
                        self.appendEvent("Import failed", "Could not read dropped file URL.")
                        return
                    }

                    self.importFileURLs([url], into: mountPoint)
                }
            }
        }

        return true
    }

    func revealVaultFile() {
        NSWorkspace.shared.activateFileViewerSelecting([runtime.vaultPath])
    }

    func revealMountedVault() {
        guard let mountPoint else { return }
        NSWorkspace.shared.open(mountPoint)
    }

    private func importFileURLs(_ urls: [URL], into mountPoint: URL) {
        do {
            let imported = try runtime.importItems(urls, into: mountPoint)
            items = runtime.listItems(at: mountPoint)
            for item in imported {
                appendEvent("Imported \(item.name)", item.sizeDescription)
                vaultDogBridge.addGuardedFile(name: item.name, kind: item.kind)
            }
        } catch {
            appendEvent("Import failed", error.localizedDescription)
        }
    }

    private func saveSecretForBiometrics(_ passphrase: String) {
        guard keychain.canEvaluateBiometrics() else {
            canUnlockWithBiometrics = false
            biometricStatusText = "Touch ID is not available on this Mac"
            appendEvent("Touch ID skipped", biometricStatusText)
            return
        }

        do {
            try keychain.save(passphrase: passphrase, for: selectedIdentity)
            canUnlockWithBiometrics = true
            biometricStatusText = "Touch ID ready for \(selectedIdentity.displayName)"
            appendEvent("Touch ID enabled", "Future unlocks for \(selectedIdentity.displayName) can use biometric authentication.")
        } catch {
            canUnlockWithBiometrics = false
            biometricStatusText = "Touch ID setup failed"
            appendEvent("Touch ID setup failed", error.localizedDescription)
        }
    }

    private func appendEvent(_ title: String, _ detail: String) {
        events.insert(VaultEvent(date: Date(), title: title, detail: detail), at: 0)
        if events.count > 40 {
            events.removeLast(events.count - 40)
        }
    }

    private func friendlyUnlockError(from error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = message.lowercased()

        if lowercased.contains("authentication") ||
            lowercased.contains("password") ||
            lowercased.contains("passphrase") ||
            lowercased.contains("not recognized") ||
            lowercased.contains("no mountable file systems") {
            return "Could not unlock the vault. Check the passphrase and keyboard layout, then try again."
        }

        return message.isEmpty ? "Could not unlock the vault." : message
    }
}
