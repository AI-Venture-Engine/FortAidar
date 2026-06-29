import AppKit
import Foundation
import FortAidarCore
import SwiftUI

@MainActor
final class PrototypeVaultStore: ObservableObject {
    @Published var ownerName: String {
        didSet { persistOwnerIdentity() }
    }
    @Published var ownerContact: String {
        didSet { handleAuthIdentityInputChanged() }
    }
    @Published var authMode: AuthMode {
        didSet { handleAuthModeChanged() }
    }
    @Published var state: VaultState = .working("Checking vault")
    @Published var items: [VaultItem] = []
    @Published var events: [VaultEvent] = []
    @Published var isDropTargeted = false
    @Published var passphrase = ""
    @Published var passphraseConfirmation = ""
    @Published var isPassphraseVisible = false
    @Published var passphraseFieldToken = UUID()
    @Published var canUnlockWithBiometrics = false
    @Published var canUseBiometrics = false
    @Published var biometricStatusText = "Touch ID setup pending"
    @Published var autoLockStatusText = "Auto-lock starts after unlock"
    let vaultDogBridge = VaultDogBridge()

    private let authEmailPolicy = AuthEmailPolicy()
    private let keychain = BiometricVaultSecretStore()
    private let audit = AuditLogWriter()
    private let autoLockPolicy = AutoLockPolicy(intervalSeconds: 600)
    private var mountPoint: URL?
    private var auditSessionID: String?
    private var lastVaultActivityAt: Date?
    private var autoLockTask: Task<Void, Never>?

    init() {
        UserDefaults.standard.removeObject(forKey: Self.ownerNameDefaultsKey)
        ownerName = ""
        let savedMode = UserDefaults.standard.string(forKey: Self.authModeDefaultsKey)
        let initialMode = savedMode.flatMap(AuthMode.init(rawValue:)) ?? .signIn
        authMode = initialMode
        ownerContact = authEmailPolicy.initialEmail(
            rememberedEmail: UserDefaults.standard.string(forKey: Self.ownerContactDefaultsKey),
            isRegisterMode: initialMode == .register
        )
    }

    var selectedIdentity: VaultIdentity {
        authEmailPolicy.identity(forEmail: ownerContact) ?? VaultIdentity(
            id: "email-required",
            displayName: "Email required",
            handle: "email-required",
            kind: .person
        )
    }

    var ownerSummaryText: String {
        let email = normalizedAuthEmail
        return email.isEmpty ? "Enter email to continue" : email
    }

    var hasAuthEmail: Bool {
        !normalizedAuthEmail.isEmpty
    }

    var canShowBiometricButton: Bool {
        canUseBiometrics && hasValidAuthEmail
    }

    var canRunBiometricAction: Bool {
        guard canUseBiometrics, hasValidAuthEmail, !state.isWorking else { return false }
        if state.isMounted { return true }
        return authMode == .signIn && canUnlockWithBiometrics
    }

    var authContextText: String {
        switch authMode {
        case .register:
            return "Register creates a separate local vault on this Mac. Email is a vault selector, not cloud recovery."
        case .signIn:
            return "Sign in opens the local vault for this email on this Mac. Recovery by email is not in this preview."
        }
    }

    private var normalizedAuthEmail: String {
        authEmailPolicy.canonicalize(ownerContact)
    }

    private var hasValidAuthEmail: Bool {
        authEmailPolicy.isValid(normalizedAuthEmail)
    }

    private var runtime: PrototypeVaultRuntime {
        PrototypeVaultRuntime(identity: selectedIdentity)
    }

    private var auditMountState: AuditMountState {
        mountPoint == nil ? .unmounted : .mounted
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
        "person"
    }

    func refresh() async {
        guard hasAuthEmail else {
            canUseBiometrics = keychain.canEvaluateBiometrics()
            canUnlockWithBiometrics = false
            biometricStatusText = "Enter email to use password or Touch ID"
            state = .missing
            items = []
            return
        }

        guard hasValidAuthEmail else {
            canUseBiometrics = keychain.canEvaluateBiometrics()
            canUnlockWithBiometrics = false
            biometricStatusText = "Check email before using password or Touch ID"
            state = .missing
            items = []
            return
        }

        canUseBiometrics = keychain.canEvaluateBiometrics()
        canUnlockWithBiometrics = keychain.hasStoredSecret(for: selectedIdentity)
        if canUseBiometrics {
            if canUnlockWithBiometrics {
                biometricStatusText = "Touch ID ready for \(selectedIdentity.displayName)"
            } else if authMode == .register {
                biometricStatusText = "Touch ID will be enabled after password registration"
            } else {
                biometricStatusText = "Touch ID will be saved after password sign-in"
            }
        } else {
            biometricStatusText = "Touch ID is not available on this Mac"
        }

        if let mountPoint {
            items = runtime.listItems(at: mountPoint)
            state = .unlocked(mountPoint: mountPoint)
        } else if runtime.vaultExists() {
            state = .locked
        } else {
            state = .missing
        }
    }

    func focusPassphraseField() {
        passphraseFieldToken = UUID()
    }

    func clearAuthEmailForNewLocalUser() {
        guard !state.isMounted, !state.isWorking else { return }
        authMode = .register
        ownerContact = ""
        passphrase = ""
        passphraseConfirmation = ""
        items = []
        mountPoint = nil
        canUnlockWithBiometrics = false
        cancelAutoLock(resetStatus: true)
        appendEvent("New local vault", "Enter another email and password to create a separate local vault.")
        Task { await refresh() }
    }

    func createOrUnlock() async {
        if authMode == .register {
            await registerWithPassword()
        } else {
            await signInWithPassword()
        }
    }

    func registerWithPassword() async {
        guard validateEmailForAuth() else { return }

        guard !passphrase.isEmpty else {
            appendEvent("Password required", "Enter a password to register this vault.")
            return
        }

        guard !passphraseConfirmation.isEmpty else {
            appendEvent("Confirm password", "Enter the same password twice before registering.")
            return
        }

        guard passphrase == passphraseConfirmation else {
            appendEvent("Passwords do not match", "Check the visible text or keyboard layout, then try again.")
            return
        }

        if runtime.vaultExists() {
            appendEvent("Vault already exists", "Signing in to \(normalizedAuthEmail) with the entered password.")
            let success = await createOrUnlock(passphrase: passphrase, shouldSaveSecret: true)
            if success {
                authMode = .signIn
            }
            return
        }

        let success = await createOrUnlock(passphrase: passphrase, shouldSaveSecret: true)
        if success {
            authMode = .signIn
        }
    }

    func signInWithPassword() async {
        guard validateEmailForAuth() else { return }

        guard runtime.vaultExists() else {
            appendEvent("No vault for this email", "Switch to Register to create storage for \(normalizedAuthEmail).")
            state = .missing
            return
        }

        guard !passphrase.isEmpty else {
            appendEvent("Password required", "Enter the password for \(normalizedAuthEmail).")
            return
        }

        _ = await createOrUnlock(passphrase: passphrase, shouldSaveSecret: true)
    }

    func performPrimaryVaultAction() async {
        if state.isMounted {
            await lock()
        } else {
            await createOrUnlock()
        }
    }

    func performBiometricVaultAction() async {
        if state.isMounted {
            await lockWithBiometrics()
        } else {
            await unlockWithBiometrics()
        }
    }

    func unlockWithBiometrics() async {
        guard validateEmailForAuth() else { return }

        guard runtime.vaultExists() else {
            appendEvent("No vault for this email", "Switch to Register to create storage for \(normalizedAuthEmail).")
            state = .missing
            return
        }

        guard canUnlockWithBiometrics || keychain.hasStoredSecret(for: selectedIdentity) else {
            appendEvent("Touch ID not set", "Sign in with password once to enable Touch ID for this email.")
            state = .locked
            return
        }

        do {
            state = .working("Authenticating")
            let secret = try keychain.readPassphrase(for: selectedIdentity)
            appendEvent("Authenticated", "Keychain released the vault secret for \(selectedIdentity.displayName).")
            audit.log(.biometricAuth, outcome: .allow, requester: selectedIdentity.id, target: selectedIdentity.keychainAccount, mountState: auditMountState, sessionID: nil)
            _ = await createOrUnlock(passphrase: secret, shouldSaveSecret: false)
        } catch {
            state = runtime.vaultExists() ? .locked : .missing
            appendEvent("Touch ID failed", error.localizedDescription)
            audit.log(.biometricAuth, outcome: .error, requester: selectedIdentity.id, target: selectedIdentity.keychainAccount, mountState: auditMountState, sessionID: nil)
        }
    }

    func lockWithBiometrics() async {
        guard state.isMounted else {
            await refresh()
            return
        }

        do {
            state = .working("Confirming lock")
            try await keychain.confirmBiometricAction(reason: "Lock Fort Aidar vault for \(selectedIdentity.displayName)")
            appendEvent("Touch ID confirmed", "Locking \(selectedIdentity.displayName) vault.")
            audit.log(.biometricAuth, outcome: .allow, requester: selectedIdentity.id, target: "lock-confirmation", mountState: auditMountState, sessionID: auditSessionID)
            await lockVault(successTitle: "Locked with Touch ID", cancelAutoLockTimer: true)
        } catch {
            if let mountPoint {
                state = .unlocked(mountPoint: mountPoint)
            } else {
                state = runtime.vaultExists() ? .locked : .missing
            }
            appendEvent("Touch ID lock cancelled", error.localizedDescription)
            audit.log(.biometricAuth, outcome: .error, requester: selectedIdentity.id, target: "lock-confirmation", mountState: auditMountState, sessionID: auditSessionID)
        }
    }

    func addItemsWithPicker() {
        guard state.isMounted, let mountPoint else {
            appendEvent("Add blocked", "Unlock the vault first.")
            focusPassphraseField()
            return
        }
        registerVaultActivity()

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

    private func createOrUnlock(passphrase: String, shouldSaveSecret: Bool) async -> Bool {
        let enteredPassphrase = passphrase
        let requester = selectedIdentity.id
        let target = selectedIdentity.vaultRelativePath

        do {
            if !runtime.vaultExists() {
                state = .working("Creating encrypted vault")
                appendEvent("Creating vault", "Building encrypted sparsebundle for \(selectedIdentity.displayName).")
                do {
                    try await runtime.createVault(passphrase: enteredPassphrase)
                } catch {
                    audit.log(.vaultCreate, outcome: .error, requester: requester, target: target, mountState: .unmounted, sessionID: nil)
                    throw error
                }
                appendEvent("Vault created", runtime.vaultPath.path)
                audit.log(.vaultCreate, outcome: .allow, requester: requester, target: target, mountState: .unmounted, sessionID: nil)
            }

            state = .working("Unlocking vault")
            let sessionID = UUID().uuidString
            let mountedAt: URL
            do {
                mountedAt = try await runtime.unlock(passphrase: enteredPassphrase)
            } catch {
                audit.log(.unlock, outcome: .error, requester: requester, target: target, mountState: .unmounted, sessionID: nil)
                throw error
            }
            self.passphrase = ""
            self.passphraseConfirmation = ""
            mountPoint = mountedAt
            auditSessionID = sessionID
            items = runtime.listItems(at: mountedAt)
            state = .unlocked(mountPoint: mountedAt)
            registerVaultActivity()
            appendEvent("Unlocked", "\(selectedIdentity.displayName) vault mounted for this session.")
            audit.log(.unlock, outcome: .allow, requester: requester, target: target, mountState: .mounted, sessionID: sessionID)
            rememberCurrentAuthEmail()

            if shouldSaveSecret {
                saveSecretForBiometrics(enteredPassphrase)
            }
            return true
        } catch {
            let message = friendlyUnlockError(from: error)
            state = .error(message)
            appendEvent("Unlock failed", message)
            return false
        }
    }

    func lock() async {
        await lockVault(successTitle: "Locked", cancelAutoLockTimer: true)
    }

    private func lockVault(successTitle: String, cancelAutoLockTimer: Bool) async {
        guard let mountPoint else {
            await refresh()
            return
        }

        if cancelAutoLockTimer {
            cancelAutoLock(resetStatus: false)
        }
        let lockSessionID = auditSessionID
        do {
            state = .working("Locking vault")
            try await runtime.lock(mountPoint: mountPoint)
            self.mountPoint = nil
            items = []
            state = .locked
            cancelAutoLock(resetStatus: true)
            appendEvent(successTitle, "\(selectedIdentity.displayName) vault detached.")
            audit.log(.lock, outcome: .allow, requester: selectedIdentity.id, target: selectedIdentity.vaultRelativePath, mountState: .unmounted, sessionID: lockSessionID)
            auditSessionID = nil
        } catch {
            state = .error(error.localizedDescription)
            appendEvent("Lock failed", error.localizedDescription)
            audit.log(.lock, outcome: .error, requester: selectedIdentity.id, target: selectedIdentity.vaultRelativePath, mountState: auditMountState, sessionID: lockSessionID)
            registerVaultActivity()
        }
    }

    func importProviders(_ providers: [NSItemProvider]) -> Bool {
        guard state.isMounted, let mountPoint else {
            appendEvent("Drop ignored", "Unlock the vault first.")
            return false
        }
        registerVaultActivity()

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
        registerVaultActivity()
        NSWorkspace.shared.open(mountPoint)
    }

    private func importFileURLs(_ urls: [URL], into mountPoint: URL) {
        registerVaultActivity()
        do {
            let imported = try runtime.importItems(urls, into: mountPoint)
            items = runtime.listItems(at: mountPoint)
            for item in imported {
                appendEvent("Imported \(item.name)", item.sizeDescription)
                vaultDogBridge.addGuardedFile(name: item.name, kind: item.kind)
                audit.log(.importItem, outcome: .allow, requester: selectedIdentity.id, target: item.name, mountState: .mounted, sessionID: auditSessionID)
            }
        } catch {
            appendEvent("Import failed", error.localizedDescription)
            audit.log(.importItem, outcome: .error, requester: selectedIdentity.id, target: "import", mountState: auditMountState, sessionID: auditSessionID)
        }
    }

    private func registerVaultActivity(now: Date = Date()) {
        guard mountPoint != nil else { return }
        lastVaultActivityAt = now
        autoLockStatusText = "Auto-lock after 10 min idle"
        scheduleAutoLock(from: now)
    }

    private func scheduleAutoLock(from activityAt: Date) {
        autoLockTask?.cancel()
        let deadline = autoLockPolicy.deadline(after: activityAt)
        let delay = max(0, deadline.timeIntervalSinceNow)
        let nanoseconds = UInt64(delay * 1_000_000_000)

        autoLockTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            await self?.autoLockIfIdle(expectedActivityAt: activityAt)
        }
    }

    private func autoLockIfIdle(expectedActivityAt: Date) async {
        guard let lastVaultActivityAt,
              lastVaultActivityAt == expectedActivityAt,
              mountPoint != nil
        else {
            return
        }

        guard autoLockPolicy.shouldLock(lastActivityAt: lastVaultActivityAt, now: Date()) else {
            scheduleAutoLock(from: lastVaultActivityAt)
            return
        }

        appendEvent("Auto-lock", "Idle timer expired after 10 minutes.")
        await lockVault(successTitle: "Auto-locked", cancelAutoLockTimer: false)
    }

    private func cancelAutoLock(resetStatus: Bool) {
        autoLockTask?.cancel()
        autoLockTask = nil
        lastVaultActivityAt = nil

        if resetStatus {
            autoLockStatusText = "Auto-lock starts after unlock"
        }
    }

    private func saveSecretForBiometrics(_ passphrase: String) {
        guard keychain.canEvaluateBiometrics() else {
            canUnlockWithBiometrics = false
            biometricStatusText = "Touch ID is not available on this Mac"
            appendEvent("Touch ID skipped", biometricStatusText)
            audit.log(.keychainStore, outcome: .deny, requester: selectedIdentity.id, target: selectedIdentity.keychainAccount, mountState: auditMountState, sessionID: auditSessionID)
            return
        }

        do {
            try keychain.save(passphrase: passphrase, for: selectedIdentity)
            canUnlockWithBiometrics = true
            biometricStatusText = "Touch ID ready for \(selectedIdentity.displayName)"
            appendEvent("Touch ID enabled", "Future unlocks for \(selectedIdentity.displayName) can use biometric authentication.")
            audit.log(.keychainStore, outcome: .allow, requester: selectedIdentity.id, target: selectedIdentity.keychainAccount, mountState: auditMountState, sessionID: auditSessionID)
        } catch {
            canUnlockWithBiometrics = false
            biometricStatusText = "Touch ID setup failed; password sign-in still works"
            appendEvent("Touch ID setup failed", "\(error.localizedDescription) Password sign-in still works.")
            audit.log(.keychainStore, outcome: .error, requester: selectedIdentity.id, target: selectedIdentity.keychainAccount, mountState: auditMountState, sessionID: auditSessionID)
        }
    }

    private func appendEvent(_ title: String, _ detail: String) {
        events.insert(VaultEvent(date: Date(), title: title, detail: detail), at: 0)
        if events.count > 40 {
            events.removeLast(events.count - 40)
        }
    }

    private func handleAuthIdentityInputChanged() {
        guard !state.isMounted else { return }
        passphrase = ""
        passphraseConfirmation = ""
        items = []
        mountPoint = nil
        cancelAutoLock(resetStatus: true)
        Task { await refresh() }
    }

    private func handleAuthModeChanged() {
        UserDefaults.standard.set(authMode.rawValue, forKey: Self.authModeDefaultsKey)
        guard !state.isMounted else { return }
        passphrase = ""
        passphraseConfirmation = ""
        items = []
        mountPoint = nil
        cancelAutoLock(resetStatus: true)

        switch authMode {
        case .register:
            if !ownerContact.isEmpty {
                ownerContact = ""
            }
        case .signIn:
            if normalizedAuthEmail.isEmpty {
                ownerContact = authEmailPolicy.initialEmail(
                    rememberedEmail: UserDefaults.standard.string(forKey: Self.ownerContactDefaultsKey),
                    isRegisterMode: false
                )
            }
        }

        Task { await refresh() }
    }

    private func persistOwnerIdentity() {
        UserDefaults.standard.removeObject(forKey: Self.ownerNameDefaultsKey)
    }

    private func rememberCurrentAuthEmail() {
        let email = normalizedAuthEmail
        guard authEmailPolicy.isValid(email) else { return }
        UserDefaults.standard.removeObject(forKey: Self.ownerNameDefaultsKey)
        UserDefaults.standard.set(email, forKey: Self.ownerContactDefaultsKey)
    }

    private func validateEmailForAuth() -> Bool {
        let email = normalizedAuthEmail
        guard !email.isEmpty else {
            appendEvent("Email required", "Enter your email before signing in or registering.")
            state = .missing
            return false
        }

        guard authEmailPolicy.isValid(email) else {
            appendEvent("Check email", "Use a normal email with Latin letters, numbers, dots, dashes, underscores, or plus signs.")
            state = .missing
            return false
        }

        return true
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

    private static let ownerNameDefaultsKey = "FortAidar.ownerName"
    private static let ownerContactDefaultsKey = "FortAidar.ownerContact"
    private static let authModeDefaultsKey = "FortAidar.authMode"
}
