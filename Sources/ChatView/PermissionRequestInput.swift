import AgentConversation
import Foundation

/// The input of a permission request, taken one member at a time. The
/// members that no part of the request took show as the rest, so no member
/// of the input stays hidden from the user.
struct PermissionRequestInput {
    private(set) var members: [String: JSONValue]

    init(_ input: JSONValue) {
        if case .object(let members) = input {
            self.members = members
        } else {
            members = input == .null ? [:] : ["input": input]
        }
    }

    /// Takes a member as text. A list of texts, such as a command in
    /// parts, joins with spaces.
    mutating func text(_ key: String) -> String? {
        guard let value = members[key] else { return nil }
        if case .array(let items) = value, items.allSatisfy({ $0.string != nil }) {
            members[key] = nil
            return items.compactMap(\.string).joined(separator: " ")
        }
        guard let text = value.string else { return nil }
        members[key] = nil
        return text
    }

    /// Takes a member as it is.
    mutating func value(_ key: String) -> JSONValue? {
        defer { members[key] = nil }
        return members[key]
    }

    /// The members that are left, one after the other, such as
    /// `timeout: 60000`. A text shows as it is, and any other value as JSON.
    var rest: String {
        members.keys.sorted().map { key in
            let value = members[key] ?? .null
            return key + ": " + (value.string ?? Self.json(value))
        }.joined(separator: "\n")
    }

    static func json(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
    }
}
