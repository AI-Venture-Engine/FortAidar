import Foundation
import FortAidarCore
import LocalAuthentication
import Security

struct BiometricVaultSecretStore: Sendable {
    private let service = "ai.aiventureengine.FortAidar"

    func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func hasStoredSecret(for identity: VaultIdentity) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.keychainAccount,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func save(passphrase: String, for identity: VaultIdentity) throws {
        delete(for: identity)

        do {
            try add(passphrase: passphrase, for: identity, flags: .biometryCurrentSet)
            return
        } catch {
            // Fall through to broader Keychain compatibility modes.
        }

        do {
            try add(passphrase: passphrase, for: identity, flags: .userPresence)
            return
        } catch {
            // Fall through to preview mode guarded by app-side Touch ID.
        }

        do {
            try addPortable(passphrase: passphrase, for: identity)
        } catch {
            throw error
        }
    }

    private func add(passphrase: String, for identity: VaultIdentity, flags: SecAccessControlCreateFlags) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            nil
        ) else {
            throw KeychainSecretError.accessControlUnavailable
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.keychainAccount,
            kSecValueData as String: Data(passphrase.utf8),
            kSecAttrAccessControl as String: access
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainSecretError.unhandledStatus(status)
        }
    }

    private func addPortable(passphrase: String, for identity: VaultIdentity) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.keychainAccount,
            kSecValueData as String: Data(passphrase.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainSecretError.unhandledStatus(status)
        }
    }

    func readPassphrase(for identity: VaultIdentity) async throws -> String {
        let context = LAContext()
        let reason = "Unlock Fort Aidar vault for \(identity.displayName)"
        context.localizedReason = reason
        try await evaluateBiometricAction(reason: reason, context: context)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainSecretError.unhandledStatus(status)
        }

        guard let data = result as? Data,
              let passphrase = String(data: data, encoding: .utf8)
        else {
            throw KeychainSecretError.invalidData
        }

        return passphrase
    }

    func confirmBiometricAction(reason: String) async throws {
        let context = LAContext()
        try await evaluateBiometricAction(reason: reason, context: context)
    }

    private func evaluateBiometricAction(reason: String, context: LAContext) async throws {
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error ?? KeychainSecretError.biometricUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? KeychainSecretError.biometricUnavailable)
                }
            }
        }
    }

    func delete(for identity: VaultIdentity) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainSecretError: LocalizedError {
    case accessControlUnavailable
    case biometricUnavailable
    case invalidData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .accessControlUnavailable:
            return "Could not create biometric Keychain access control."
        case .biometricUnavailable:
            return "Biometric authentication is not available on this Mac."
        case .invalidData:
            return "Stored Keychain secret is not readable."
        case .unhandledStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error \(status)."
        }
    }
}
