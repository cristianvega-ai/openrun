import AgentConversation

/// The identifier of a request of the app-server protocol.
///
/// The protocol is JSON-RPC, where an identifier is a number or a string.
/// OpenRun numbers its own requests. Codex numbers the requests that it
/// sends to OpenRun, such as an approval, and the answer must carry the
/// identifier exactly as it came.
enum CodexRequestIdentifier: Sendable, Hashable, CustomStringConvertible {
    case number(Int)
    case text(String)

    /// Nil for a value that is no identifier, such as a fraction or null.
    init?(_ value: JSONValue) {
        if let number = value.integer {
            self = .number(number)
        } else if let text = value.string {
            self = .text(text)
        } else {
            return nil
        }
    }

    var jsonValue: JSONValue {
        switch self {
        case .number(let number): .number(Double(number))
        case .text(let text): .string(text)
        }
    }

    var description: String {
        switch self {
        case .number(let number): String(number)
        case .text(let text): text
        }
    }
}
