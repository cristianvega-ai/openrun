import AgentConversation
import Foundation

/// The lines that OpenRun writes to the standard input of the app-server.
///
/// Each one is one JSON object and a line end. The encoder escapes every
/// line end inside a string, so a message never spans two lines.
enum CodexOutgoingLine {
    static func request(_ identifier: CodexRequestIdentifier, method: String, parameters: JSONValue) throws -> [UInt8] {
        try line(["id": identifier.jsonValue, "method": .string(method), "params": parameters])
    }

    static func notification(method: String, parameters: JSONValue) throws -> [UInt8] {
        try line(["method": .string(method), "params": parameters])
    }

    /// The answer to a request of the server, with its identifier as it came.
    static func response(to identifier: CodexRequestIdentifier, result: JSONValue) throws -> [UInt8] {
        try line(["id": identifier.jsonValue, "result": result])
    }

    /// The refusal of a request of the server that OpenRun does not serve.
    static func failure(to identifier: CodexRequestIdentifier, code: Int, message: String) throws -> [UInt8] {
        try line(["id": identifier.jsonValue, "error": .object(["code": .number(Double(code)), "message": .string(message)])])
    }

    /// Fails only for a number that JSON cannot hold, such as infinity.
    private static func line(_ members: [String: JSONValue]) throws -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Array(try encoder.encode(JSONValue.object(members))) + [UInt8(ascii: "\n")]
    }
}
