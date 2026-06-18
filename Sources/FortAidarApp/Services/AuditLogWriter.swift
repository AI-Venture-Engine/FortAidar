import Foundation
import FortAidarCore

/// Append-only JSONL audit writer for the local preview build.
///
/// File: `~/Library/Application Support/FortAidar/audit/events.jsonl`
/// - Directory is created `0700`, file `0600` (owner-only) where supported.
/// - Writes are serialized on a private queue so concurrent GUI callbacks
///   cannot interleave partial lines.
/// - Best-effort: an audit failure is logged but never crashes the app.
/// - Lives outside the encrypted vault and outside any agent logical namespace.
final class AuditLogWriter: AuditSink, @unchecked Sendable {
    private let codec = AuditEventCodec()
    private let queue = DispatchQueue(label: "com.aiventureengine.fortaidar.audit")
    private let fileManager = FileManager.default

    var auditDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("FortAidar", isDirectory: true)
            .appendingPathComponent("audit", isDirectory: true)
    }

    var eventsFileURL: URL {
        auditDirectory.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    func record(_ event: AuditEvent) {
        queue.async { [weak self] in
            self?.write(event)
        }
    }

    /// Convenience that builds and records an event without exposing the
    /// on-disk format or `AuditEvent` plumbing to the UI layer.
    func log(
        _ operation: AuditOperation,
        outcome: AuditOutcome,
        requester: String,
        target: String,
        mountState: AuditMountState,
        sessionID: String?,
        grant: String? = nil
    ) {
        let event = AuditEvent(
            wallTime: Date(),
            monotonicNanos: DispatchTime.now().uptimeNanoseconds,
            requester: requester,
            operation: operation,
            logicalTargetPath: target,
            outcome: outcome,
            grant: grant,
            mountState: mountState,
            sessionID: sessionID
        )
        record(event)
    }

    private func write(_ event: AuditEvent) {
        do {
            let line = try codec.line(for: event) + "\n"
            guard let data = line.data(using: .utf8) else { return }
            try ensureStorePrepared()
            let handle = try FileHandle(forWritingTo: eventsFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(data)
        } catch {
            // Audit logging is best-effort in the preview; never crash the app.
            NSLog("FortAidar audit write failed: %@", error.localizedDescription)
        }
    }

    private func ensureStorePrepared() throws {
        if !fileManager.fileExists(atPath: auditDirectory.path) {
            try fileManager.createDirectory(
                at: auditDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        chmod(auditDirectory.path, 0o700)

        if !fileManager.fileExists(atPath: eventsFileURL.path) {
            fileManager.createFile(
                atPath: eventsFileURL.path,
                contents: Data(),
                attributes: [.posixPermissions: 0o600]
            )
        }
        chmod(eventsFileURL.path, 0o600)
    }
}
