import CryptoKit
import Foundation

public enum VaultIdentityKind: String, Codable, CaseIterable, Sendable {
    case person
    case agent
}

public struct VaultIdentity: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let handle: String
    public let kind: VaultIdentityKind

    public init(id: String, displayName: String, handle: String, kind: VaultIdentityKind) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.kind = kind
    }

    public var keychainAccount: String {
        "vault-passphrase:\(id)"
    }

    public var vaultRelativePath: String {
        id == "default" ? "FortAidar.sparsebundle" : "Vaults/\(id)/FortAidar.sparsebundle"
    }
}

public struct AuthEmailPolicy: Sendable {
    public init() {}

    public func initialEmail(rememberedEmail: String?, isRegisterMode: Bool) -> String {
        guard !isRegisterMode else { return "" }
        return canonicalize(rememberedEmail ?? "")
    }

    public func identity(forEmail value: String) -> VaultIdentity? {
        let email = canonicalize(value)
        guard isValid(email), let id = identityID(forEmail: email) else {
            return nil
        }

        return VaultIdentity(
            id: id,
            displayName: email,
            handle: email,
            kind: .person
        )
    }

    public func identityID(forEmail value: String) -> String? {
        let email = canonicalize(value)
        guard isValid(email) else {
            return nil
        }

        let slug = slugComponent(from: email)
        let digest = SHA256.hash(data: Data(email.utf8))
        let shortHash = digest.map { String(format: "%02x", $0) }.joined().prefix(10)
        return "user-\(slug)-\(shortHash)"
    }

    public func canonicalize(_ value: String) -> String {
        let homographMap: [Unicode.Scalar: String] = [
            "а": "a", "А": "a",
            "е": "e", "Е": "e",
            "о": "o", "О": "o",
            "р": "p", "Р": "p",
            "с": "c", "С": "c",
            "у": "y", "У": "y",
            "х": "x", "Х": "x",
            "к": "k", "К": "k",
            "м": "m", "М": "m",
            "т": "t", "Т": "t",
            "в": "b", "В": "b",
            "н": "h", "Н": "h",
            "і": "i", "І": "i",
            "ї": "i", "Ї": "i",
            "ј": "j", "Ј": "j",
            "ѕ": "s", "Ѕ": "s"
        ]

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = ""
        for scalar in trimmed.unicodeScalars {
            if let replacement = homographMap[scalar] {
                normalized.append(replacement)
            } else {
                normalized.append(String(scalar))
            }
        }
        return normalized.lowercased()
    }

    public func isValid(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._%+-@")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return false
        }

        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              parts[1].contains(".")
        else {
            return false
        }

        let domainLabels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domainLabels.allSatisfy { !$0.isEmpty }
    }

    private func slugComponent(from value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var result = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.append(String(scalar))
            } else if !result.hasSuffix("-") {
                result.append("-")
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "email" : trimmed
    }
}

public struct ResolvedLogicalPath: Equatable, Sendable {
    public let relativePath: String
    public let auditNamespace: String
}

public enum LogicalPathError: Error, Equatable, Sendable {
    case invalidAgentID
    case invalidNamespace
    case foreignNamespace
    case traversal
    case emptyPath
}

public struct LogicalPathPolicy: Sendable {
    public init() {}

    public func resolve(agentID: String, namespace: String, path: String) throws -> ResolvedLogicalPath {
        let cleanAgentID = try cleanPathComponent(agentID, error: .invalidAgentID)
        let expectedNamespace = "agents/\(cleanAgentID)"
        let cleanNamespace = try cleanRelativePath(namespace, error: .invalidNamespace)

        guard cleanNamespace == expectedNamespace else {
            throw LogicalPathError.foreignNamespace
        }

        let cleanPath = try cleanRelativePath(path, error: .emptyPath)
        let relativePath = "\(cleanNamespace)/\(cleanPath)"

        return ResolvedLogicalPath(relativePath: relativePath, auditNamespace: cleanNamespace)
    }

    private func cleanPathComponent(_ value: String, error: LogicalPathError) throws -> String {
        guard !value.isEmpty, !value.contains("/"), value != ".", value != ".." else {
            throw error
        }
        return value
    }

    private func cleanRelativePath(_ value: String, error: LogicalPathError) throws -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else {
            throw error
        }
        guard !parts.contains("."), !parts.contains("..") else {
            throw LogicalPathError.traversal
        }
        return parts.joined(separator: "/")
    }
}

public struct HdiutilCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let requiresPassphraseOnStdin: Bool

    public static func attach(sparsebundlePath: String, mountPoint: String) -> HdiutilCommand {
        HdiutilCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                sparsebundlePath,
                "-mountpoint",
                mountPoint,
                "-stdinpass",
                "-nobrowse",
                "-noautoopen"
            ],
            requiresPassphraseOnStdin: true
        )
    }

    public static func detach(mountPoint: String, force: Bool) -> HdiutilCommand {
        var arguments = ["detach", mountPoint]
        if force {
            arguments.append("-force")
        }

        return HdiutilCommand(
            executable: "/usr/bin/hdiutil",
            arguments: arguments,
            requiresPassphraseOnStdin: false
        )
    }
}

public struct FortStatus: Equatable, Codable, Sendable {
    public let mounted: Bool
    public let mountPoint: String?
    public let unlockedBy: String?
    public let ttlSeconds: Int?

    public init(mounted: Bool, mountPoint: String?, unlockedBy: String?, ttlSeconds: Int?) {
        self.mounted = mounted
        self.mountPoint = mountPoint
        self.unlockedBy = unlockedBy
        self.ttlSeconds = ttlSeconds
    }

    public func redactedForAgent() -> FortStatus {
        FortStatus(
            mounted: mounted,
            mountPoint: nil,
            unlockedBy: unlockedBy,
            ttlSeconds: ttlSeconds
        )
    }
}

public struct AutoLockPolicy: Equatable, Sendable {
    public let intervalSeconds: TimeInterval

    public init(intervalSeconds: TimeInterval) {
        self.intervalSeconds = intervalSeconds
    }

    public func deadline(after activityAt: Date) -> Date {
        activityAt.addingTimeInterval(intervalSeconds)
    }

    public func shouldLock(lastActivityAt: Date, now: Date) -> Bool {
        now >= deadline(after: lastActivityAt)
    }
}

public enum FortMethod: String, CaseIterable, Codable, Sendable {
    case status = "fortaidar.status"
    case unlock = "fortaidar.unlock"
    case lock = "fortaidar.lock"
    case list = "fortaidar.list"
    case get = "fortaidar.get"
    case put = "fortaidar.put"
    case audit = "fortaidar.audit"
}

public struct SessionTokenIssuer: Sendable {
    private let secret: SymmetricKey

    public init(secret: Data) {
        self.secret = SymmetricKey(data: secret)
    }

    public func issue(agentID: String, namespace: String, expiresAt: Date) -> String {
        let expiresAtSeconds = Int(expiresAt.timeIntervalSince1970)
        let payload = "\(agentID)|\(namespace)|\(expiresAtSeconds)"
        let signature = signatureHex(for: payload)
        return "\(base64URLEncode(Data(payload.utf8))).\(signature)"
    }

    public func verify(_ token: String, agentID: String, namespace: String, now: Date) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadData = base64URLDecode(String(parts[0])),
              let payload = String(data: payloadData, encoding: .utf8)
        else {
            return false
        }

        let payloadParts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard payloadParts.count == 3,
              payloadParts[0] == agentID,
              payloadParts[1] == namespace,
              let expiresAtSeconds = TimeInterval(payloadParts[2])
        else {
            return false
        }

        guard now.timeIntervalSince1970 <= expiresAtSeconds else {
            return false
        }

        let expectedSignature = signatureHex(for: payload)
        return constantTimeEquals(expectedSignature, String(parts[1]))
    }

    private func signatureHex(for payload: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: secret)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

public enum AuditOperation: String, Codable, Sendable {
    // Core / MCP-facing operations.
    case unlock
    case lock
    case mount
    case unmount
    case list
    case read
    case put
    case delete
    case export
    case grantChange
    case passphraseOperation

    // App-side (GUI) operations recorded by the local audit log.
    // Added for the human-side preview events listed in the Audit v1 slice
    // (vault create, identity switch, file import, biometric/keychain).
    case vaultCreate
    case identitySwitch
    case importItem
    case biometricAuth
    case keychainStore
}

public enum AuditOutcome: String, Codable, Sendable {
    case allow
    case deny
    case error
}

public enum AuditMountState: String, Codable, Sendable {
    case mounted
    case unmounted
    case orphan
}

public struct AuditEvent: Equatable, Codable, Sendable {
    public let wallTime: Date
    public let monotonicNanos: UInt64
    public let requester: String
    public let operation: AuditOperation
    public let logicalTargetPath: String
    public let outcome: AuditOutcome
    public let grant: String?
    public let mountState: AuditMountState
    public let sessionID: String?

    public init(
        wallTime: Date,
        monotonicNanos: UInt64,
        requester: String,
        operation: AuditOperation,
        logicalTargetPath: String,
        outcome: AuditOutcome,
        grant: String?,
        mountState: AuditMountState,
        sessionID: String?
    ) {
        self.wallTime = wallTime
        self.monotonicNanos = monotonicNanos
        self.requester = requester
        self.operation = operation
        self.logicalTargetPath = logicalTargetPath
        self.outcome = outcome
        self.grant = grant
        self.mountState = mountState
        self.sessionID = sessionID
    }
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func base64URLDecode(_ value: String) -> Data? {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    while base64.count % 4 != 0 {
        base64.append("=")
    }

    return Data(base64Encoded: base64)
}

private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let lhsBytes = Array(lhs.utf8)
    let rhsBytes = Array(rhs.utf8)
    guard lhsBytes.count == rhsBytes.count else {
        return false
    }

    var difference: UInt8 = 0
    for index in lhsBytes.indices {
        difference |= lhsBytes[index] ^ rhsBytes[index]
    }
    return difference == 0
}
