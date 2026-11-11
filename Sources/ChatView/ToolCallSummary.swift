import AgentConversation
import Foundation

/// The words and the symbol of a tool call on its compact line.
struct ToolCallSummary: Equatable {
    var symbolName: String
    /// What the call does, such as "Read Transcript.swift".
    var title: String
    /// The main input in full, such as a path or a command, for the open
    /// line.
    var subject: String?
    /// The state when the call did not succeed, such as "Exit code 1".
    var status: String?

    init(_ call: ToolCallItem) {
        func input(_ key: String) -> String? {
            guard case .object(let members)? = call.input, case .string(let value)? = members[key] else { return nil }
            return value
        }
        let path = input("file_path") ?? input("notebook_path")
        let file = path.map { ($0 as NSString).lastPathComponent } ?? "a file"
        switch call.name {
        case "Bash":
            let command = input("command")
            symbolName = "terminal"
            title = input("description") ?? "Ran " + (command?.split(separator: "\n").first.map(String.init) ?? "a command")
            subject = command
        case "Read": (symbolName, title, subject) = ("doc.text", "Read " + file, path)
        case "Edit", "MultiEdit", "NotebookEdit": (symbolName, title, subject) = ("pencil", "Edited " + file, path)
        case "Write": (symbolName, title, subject) = ("pencil", "Wrote " + file, path)
        case "Grep": (symbolName, title, subject) = ("magnifyingglass", "Searched for “\(input("pattern") ?? "")”", input("path"))
        case "Glob": (symbolName, title, subject) = ("magnifyingglass", "Listed files like \(input("pattern") ?? "")", input("path"))
        case "WebFetch":
            let address = input("url")
            (symbolName, title, subject) = ("globe", "Read " + (address.flatMap { URL(string: $0)?.host() } ?? "a web page"), address)
        case "WebSearch": (symbolName, title, subject) = ("globe", "Searched the web for “\(input("query") ?? "")”", nil)
        case "TodoWrite": (symbolName, title, subject) = ("checklist", "Updated the to-do list", nil)
        default: (symbolName, title, subject) = ("wrench.and.screwdriver", call.name, nil)
        }
        status = switch call.state {
        case .preparing, .running: "Running"
        case .succeeded: nil
        case .failed: call.exitCode.map { "Exit code \($0)" } ?? "Failed"
        case .refused: "Refused"
        case .interrupted: "Stopped"
        }
    }

    /// One line for a run of calls, such as "Read 2 files, searched 2 times".
    static func title(ofRun calls: [ToolCallItem]) -> String {
        var counts: [(verb: String, one: String, many: String, count: Int)] = []
        for call in calls {
            let kind: (String, String, String) = switch call.name {
            case "Read": ("read", "file", "files")
            case "Edit", "MultiEdit", "NotebookEdit", "Write": ("edited", "file", "files")
            case "Grep", "Glob", "WebSearch": ("searched", "time", "times")
            case "Bash": ("ran", "command", "commands")
            case "WebFetch": ("read", "web page", "web pages")
            default: ("used", "tool", "tools")
            }
            if let index = counts.firstIndex(where: { $0.verb == kind.0 && $0.one == kind.1 }) {
                counts[index].count += 1
            } else {
                counts.append((kind.0, kind.1, kind.2, 1))
            }
        }
        let parts = counts.map { "\($0.verb) \($0.count) \($0.count == 1 ? $0.one : $0.many)" }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The input and the output of a call. Its box scrolls, so it holds
    /// all of the output that the transcript kept.
    static func detail(of call: ToolCallItem, subject: String?) -> [(text: String, note: String?)] {
        var parts: [(text: String, note: String?)] = [(subject ?? call.inputText, nil)]
        if !call.output.isEmpty {
            let isCut = call.outputByteCount > call.output.utf8.count
            parts.append((call.output, isCut ? "More output was not kept" : nil))
        }
        return parts
    }
}
