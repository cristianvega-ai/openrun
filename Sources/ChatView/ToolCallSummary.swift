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

}
