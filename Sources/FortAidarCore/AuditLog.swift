import Foundation

/// Errors raised while serializing or parsing audit lines.
public enum AuditCodecError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}

/// Serializes `AuditEvent` values to and from a single JSON line (JSONL).
///
/// Output is deterministic (sorted keys) and self-contained: each event is one
/// line with no embedded newlines, so the audit file stays append-only and
/// line-oriented. `AuditEvent` has no secret fields by construction, so a
/// passphrase can never be serialized here.
public struct AuditEventCodec: Sendable {
    public init() {}

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// One self-contained JSON line for the event (no embedded newlines).
    public func line(for event: AuditEvent) throws -> String {
        let data = try encoder.encode(event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AuditCodecError.encodingFailed
        }
        // JSONEncoder never emits raw control newlines, but normalize defensively
        // so a single event can never span more than one JSONL line.
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Parses a single JSONL line back into an `AuditEvent`.
    public func event(from line: String) throws -> AuditEvent {
        guard let data = line.data(using: .utf8) else {
            throw AuditCodecError.decodingFailed
        }
        return try decoder.decode(AuditEvent.self, from: data)
    }
}

/// Append-only audit destination. Implementations persist one event per call
/// without coupling callers to the on-disk format.
public protocol AuditSink: Sendable {
    func record(_ event: AuditEvent)
}
