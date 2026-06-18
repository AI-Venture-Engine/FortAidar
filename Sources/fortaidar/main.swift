import Darwin
import Foundation
import FortAidarCore

private let supportedProtocolVersion = "2025-11-25"
private let serverName = "fort-aidar"
private let serverVersion = "0.1.0-preview"

while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }

    if let response = handleJSONRPCLine(trimmed) {
        print(encodeJSONObject(response))
        fflush(stdout)
    }
}

private func handleJSONRPCLine(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8) else {
        return errorResponse(id: NSNull(), code: -32700, message: "Parse error")
    }

    do {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let request = object as? [String: Any] else {
            return errorResponse(id: NSNull(), code: -32600, message: "Invalid request")
        }

        let id = request["id"]
        guard let method = request["method"] as? String else {
            return errorResponse(id: id ?? NSNull(), code: -32600, message: "Invalid request")
        }

        if id == nil {
            return handleNotification(method: method)
        }

        switch method {
        case "initialize":
            return successResponse(id: id, result: initializeResult(params: request["params"]))
        case "tools/list":
            return successResponse(id: id, result: ["tools": [statusToolDefinition()]])
        case "tools/call":
            return handleToolCall(id: id, params: request["params"])
        case FortMethod.status.rawValue:
            return successResponse(id: id, result: redactedStatusDictionary())
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    } catch {
        return errorResponse(id: NSNull(), code: -32700, message: "Parse error")
    }
}

private func handleNotification(method: String) -> [String: Any]? {
    switch method {
    case "notifications/initialized", "notifications/cancelled":
        return nil
    default:
        return nil
    }
}

private func initializeResult(params: Any?) -> [String: Any] {
    let requestedVersion = ((params as? [String: Any])?["protocolVersion"] as? String) ?? supportedProtocolVersion
    let protocolVersion = requestedVersion == supportedProtocolVersion ? requestedVersion : supportedProtocolVersion

    return [
        "protocolVersion": protocolVersion,
        "capabilities": [
            "tools": [
                "listChanged": false
            ]
        ],
        "serverInfo": [
            "name": serverName,
            "title": "Fort Aidar",
            "version": serverVersion,
            "description": "Preview local encrypted vault server for Fort Aidar."
        ],
        "instructions": "Preview build: only fortaidar.status is exposed over MCP stdio. Unlocking and file import remain human-controlled in the macOS app."
    ]
}

private func handleToolCall(id: Any?, params: Any?) -> [String: Any] {
    guard let params = params as? [String: Any],
          let name = params["name"] as? String
    else {
        return errorResponse(id: id, code: -32602, message: "Invalid tools/call params")
    }

    guard name == FortMethod.status.rawValue else {
        return errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)")
    }

    let status = redactedStatusDictionary()
    return successResponse(id: id, result: [
        "content": [
            [
                "type": "text",
                "text": encodeJSONObject(status)
            ]
        ],
        "structuredContent": status,
        "isError": false
    ])
}

private func statusToolDefinition() -> [String: Any] {
    [
        "name": FortMethod.status.rawValue,
        "title": "Fort Aidar Status",
        "description": "Return redacted local Fort Aidar vault status. Does not reveal the real mount path.",
        "inputSchema": [
            "type": "object",
            "additionalProperties": false
        ],
        "outputSchema": [
            "type": "object",
            "properties": [
                "mounted": ["type": "boolean"],
                "mountPoint": ["type": ["string", "null"]],
                "unlockedBy": ["type": ["string", "null"]],
                "ttlSeconds": ["type": ["integer", "null"]]
            ],
            "required": ["mounted", "mountPoint", "unlockedBy", "ttlSeconds"]
        ]
    ]
}

private func redactedStatusDictionary() -> [String: Any] {
    let status = FortStatus(
        mounted: false,
        mountPoint: nil,
        unlockedBy: nil,
        ttlSeconds: nil
    ).redactedForAgent()

    return [
        "mounted": status.mounted,
        "mountPoint": status.mountPoint ?? NSNull(),
        "unlockedBy": status.unlockedBy ?? NSNull(),
        "ttlSeconds": status.ttlSeconds ?? NSNull()
    ]
}

private func successResponse(id: Any?, result: [String: Any]) -> [String: Any] {
    [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "result": result
    ]
}

private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
    [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "error": [
            "code": code,
            "message": message
        ]
    ]
}

private func encodeJSONObject(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
    }

    return text
}
