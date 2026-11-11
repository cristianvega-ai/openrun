import AgentConversation
import Foundation

/// The words of a permission request: what the agent wants to do, and the
/// command, path or input that the user must read before an answer.
struct PermissionRequestWords: Equatable {
    var title: String
    /// The text that the request is about, with each control character and
    /// each mark of text direction shown, so nothing hides in it.
    var subject: String

    init(_ item: PermissionRequestItem, agentName: String) {
        let request = item.request
        func input(_ key: String) -> String? {
            guard case .object(let members) = request.input, case .string(let value)? = members[key] else { return nil }
            return value
        }
        let (action, subject): (String, String?) = switch request.toolName {
        case "Bash": ("run a command", input("command"))
        case "Edit", "MultiEdit", "NotebookEdit": ("edit a file", input("file_path") ?? input("notebook_path"))
        case "Write": ("write a file", input("file_path"))
        case "WebFetch": ("read a web page", input("url"))
        default: ("use \(request.toolName)", nil)
        }
        title = "\(agentName) wants to \(action)"
        self.subject = Self.bounded(Self.visible(subject ?? Self.lines(of: request.input)))
    }

    /// The input as one line for each member, such as `path: /tmp`.
    static func lines(of input: JSONValue) -> String {
        guard case .object(let members) = input else { return "\(input)" }
        return members.keys.sorted().map { key in
            guard case .string(let value)? = members[key] else { return "\(key): \(members[key] ?? .null)" }
            return "\(key): \(value)"
        }.joined(separator: "\n")
    }

    /// The text with control characters, other than a line end or a tab,
    /// and format characters shown as marks or codes. A direction override
    /// or a zero-width space can hide or reorder what the user reads.
    static func visible(_ text: String) -> String {
        var shown = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A, 0x09: shown.unicodeScalars.append(scalar)
            case 0x0D: shown += "⏎"
            case 0x1B: shown += "⎋"
            case 0x00..<0x20: shown += "^" + String(UnicodeScalar(UInt8(scalar.value + 0x40)))
            case 0x7F: shown += "⌫"
            case 0x80...0x9F: shown += code(of: scalar)
            default:
                switch scalar.properties.generalCategory {
                case .format, .lineSeparator, .paragraphSeparator: shown += code(of: scalar)
                default: shown.unicodeScalars.append(scalar)
                }
            }
        }
        return shown
    }

    private static func code(of scalar: Unicode.Scalar) -> String {
        "⟨U+" + String(format: "%04X", scalar.value) + "⟩"
    }

    /// A very long text keeps its start and its end, where a command
    /// usually puts what it does.
    static func bounded(_ text: String, limit: Int = 4_000) -> String {
        guard text.count > limit else { return text }
        let hidden = text.count - limit
        return text.prefix(limit / 2) + "\n… \(hidden) characters not shown …\n" + text.suffix(limit / 2)
    }
}
