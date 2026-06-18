import Foundation
import FortAidarCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("Spec failed: \(message)")
    }
}

func expectThrows(_ message: String, _ operation: () throws -> Void) {
    do {
        try operation()
        fatalError("Spec failed: \(message)")
    } catch {
        return
    }
}

func specLogicalPathPolicy() throws {
    let policy = LogicalPathPolicy()

    let resolved = try policy.resolve(
        agentID: "oc1",
        namespace: "agents/oc1",
        path: "reviews/report.md"
    )
    expect(resolved.relativePath == "agents/oc1/reviews/report.md", "agent own namespace resolves")
    expect(resolved.auditNamespace == "agents/oc1", "audit namespace is preserved")

    expectThrows("traversal escape is rejected") {
        _ = try policy.resolve(agentID: "oc1", namespace: "agents/oc1", path: "../dc1/secrets.txt")
    }

    expectThrows("foreign namespace is rejected") {
        _ = try policy.resolve(agentID: "oc1", namespace: "agents/dc1", path: "patches/fix.diff")
    }
}

func specHdiutilCommandPolicy() {
    let attach = HdiutilCommand.attach(
        sparsebundlePath: "/Users/aidar/Fort.sparsebundle",
        mountPoint: "/Users/aidar/Library/Application Support/FortAidar/mnt/session-123"
    )
    expect(attach.executable == "/usr/bin/hdiutil", "hdiutil executable path")
    expect(attach.arguments.contains("-stdinpass"), "attach uses stdin passphrase")
    expect(attach.arguments.contains("-noexec"), "attach uses noexec")
    expect(attach.arguments.contains("-nosuid"), "attach uses nosuid")
    expect(attach.arguments.contains("-nodev"), "attach uses nodev")
    expect(!attach.arguments.contains("secret-passphrase"), "passphrase is never an argument")
    expect(attach.requiresPassphraseOnStdin, "stdin passphrase is marked required")

    let detach = HdiutilCommand.detach(
        mountPoint: "/Users/aidar/Library/Application Support/FortAidar/mnt/session-123",
        force: true
    )
    expect(detach.arguments == [
        "detach",
        "/Users/aidar/Library/Application Support/FortAidar/mnt/session-123",
        "-force"
    ], "force detach command arguments")
}

func specMCPContract() {
    let status = FortStatus(
        mounted: true,
        mountPoint: "/Users/aidar/Library/Application Support/FortAidar/mnt/session-123",
        unlockedBy: "cx1",
        ttlSeconds: 300
    )
    let publicStatus = status.redactedForAgent()
    expect(publicStatus.mounted, "public status includes mounted state")
    expect(publicStatus.mountPoint == nil, "public status hides real mountpoint")
    expect(publicStatus.unlockedBy == "cx1", "public status includes unlock owner")
    expect(publicStatus.ttlSeconds == 300, "public status includes ttl")

    expect(Set(FortMethod.allCases.map(\.rawValue)) == [
        "fortaidar.status",
        "fortaidar.unlock",
        "fortaidar.lock",
        "fortaidar.list",
        "fortaidar.get",
        "fortaidar.put",
        "fortaidar.audit"
    ], "known JSON-RPC methods are explicit")
}

func specSessionTokens() {
    let issuer = SessionTokenIssuer(secret: Data("test-session-secret".utf8))
    let expiry = Date(timeIntervalSince1970: 1_800)
    let token = issuer.issue(agentID: "lu2", namespace: "agents/lu2", expiresAt: expiry)

    expect(
        issuer.verify(token, agentID: "lu2", namespace: "agents/lu2", now: Date(timeIntervalSince1970: 1_700)),
        "token verifies for same agent/session before expiry"
    )
    expect(
        !issuer.verify(token, agentID: "dc1", namespace: "agents/dc1", now: Date(timeIntervalSince1970: 1_700)),
        "token rejects another agent"
    )
    expect(
        !issuer.verify(token, agentID: "lu2", namespace: "agents/lu2", now: Date(timeIntervalSince1970: 1_801)),
        "token expires"
    )
}

func specAuditEvents() {
    let event = AuditEvent(
        wallTime: Date(timeIntervalSince1970: 1_700_000_000),
        monotonicNanos: 42,
        requester: "oc1",
        operation: .put,
        logicalTargetPath: "agents/oc1/reviews/report.md",
        outcome: .allow,
        grant: "agents/oc1",
        mountState: .mounted,
        sessionID: "session-123"
    )

    expect(event.requester == "oc1", "audit requester")
    expect(event.operation == .put, "audit operation")
    expect(event.logicalTargetPath == "agents/oc1/reviews/report.md", "audit logical path")
    expect(event.outcome == .allow, "audit outcome")
    expect(event.mountState == .mounted, "audit mount state")
    expect(event.sessionID == "session-123", "audit session id")
}

func specVaultIdentityPolicy() {
    let defaultIdentity = VaultIdentity(id: "default", displayName: "Aidar local", handle: "aidar", kind: .person)
    expect(defaultIdentity.keychainAccount == "vault-passphrase:default", "default identity has scoped keychain account")
    expect(defaultIdentity.vaultRelativePath == "FortAidar.sparsebundle", "default identity preserves legacy vault path")

    let agentIdentity = VaultIdentity(id: "agent-lu2", displayName: "Lu2", handle: "lu2", kind: .agent)
    expect(agentIdentity.keychainAccount == "vault-passphrase:agent-lu2", "agent identity has scoped keychain account")
    expect(agentIdentity.vaultRelativePath == "Vaults/agent-lu2/FortAidar.sparsebundle", "agent identity has isolated vault path")
}

try specLogicalPathPolicy()
specHdiutilCommandPolicy()
specMCPContract()
specSessionTokens()
specAuditEvents()
specVaultIdentityPolicy()

print("FortAidarCoreSpec passed")
