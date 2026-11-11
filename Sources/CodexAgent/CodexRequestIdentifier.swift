import AgentConversation
import Foundation

/// The identifier of a request of the app-server protocol.
///
/// The protocol is JSON-RPC, where an identifier is a number or a string.
/// OpenRun numbers its own requests. Codex numbers the requests that it
/// sends to OpenRun, such as an approval, and the answer must carry the
/// identifier exactly as it came. So the identifier is its JSON text: a
/// number above 2^53 would change on its way through a `Double`.
struct CodexRequestIdentifier: Sendable, Hashable, CustomStringConvertible {
    /// The identifier as JSON text, such as `12` or `"a-1"`.
    let token: String

    static func number(_ number: Int) -> CodexRequestIdentifier { CodexRequestIdentifier(checkedToken: String(number)) }

    static func text(_ text: String) -> CodexRequestIdentifier {
        CodexRequestIdentifier(checkedToken: String(decoding: (try? JSONEncoder().encode(text)) ?? Data(), as: UTF8.self))
    }

    private init(checkedToken: String) { token = checkedToken }

    /// Nil for JSON text that is no whole number and no string.
    init?(token: String) {
        guard token.wholeMatch(of: /-?(0|[1-9][0-9]*)/) != nil || (try? JSONDecoder().decode(String.self, from: Data(token.utf8))) != nil else {
            return nil
        }
        self.token = token
    }

    /// Nil for a value that is no identifier, such as a fraction or null.
    /// A value from a decoded line keeps only what a `Double` holds.
    init?(_ value: JSONValue) {
        if let number = value.integer {
            self = .number(number)
        } else if let text = value.string {
            self = .text(text)
        } else {
            return nil
        }
    }

    /// The whole number of one of OpenRun's own requests.
    var number: Int? { Int(token) }

    var description: String {
        (try? JSONDecoder().decode(String.self, from: Data(token.utf8))) ?? token
    }
}
