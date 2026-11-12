/// The words after `openrun thread`.
extension CommandLineArguments {
    /// The options that a thread command can take.
    struct ThreadOptions {
        var agent: String?
        var folder: String?
        var model: String?
        var mode: String?
        var name: String?
        var printsJSON = false
    }

    /// - Parameter afterSeparator: The words after `--`: the first message
    ///   of `new`, or more text of `send` and `rename`.
    static func threadCommand(_ words: [String], afterSeparator: [String]?, options: ThreadOptions) throws -> ToolCommand {
        guard let action = words.first else {
            throw CommandLineToolError.usage("thread needs list, new, send, read, stop, rename or close.")
        }
        let rest = Array(words.dropFirst())
        func refuse(_ option: String, _ isUsed: Bool, _ commands: String) throws {
            if isUsed { throw CommandLineToolError.usage("\(option) does not belong to thread \(action). It works with \(commands).") }
        }
        if action != "new" {
            try refuse("--agent", options.agent != nil, "thread new")
            try refuse("--folder", options.folder != nil, "new and thread new")
            try refuse("--model", options.model != nil, "thread new")
            try refuse("--mode", options.mode != nil, "thread new")
            try refuse("--name", options.name != nil, "project add and thread new")
        }
        if action != "list", action != "read" { try refuse("--json", options.printsJSON, "thread list and thread read") }
        if afterSeparator != nil, !["new", "send", "rename"].contains(action) {
            throw CommandLineToolError.usage("thread \(action) takes nothing after --.")
        }
        let text = (rest.dropFirst() + (afterSeparator ?? [])).joined(separator: " ")
        switch action {
        case "list":
            guard rest.isEmpty else { throw CommandLineToolError.usage("thread list takes no arguments.") }
            return .thread(.list(printsJSON: options.printsJSON))
        case "new":
            guard rest.isEmpty else { throw CommandLineToolError.usage("thread new takes no identifier. Put the first message after --.") }
            let message = (afterSeparator ?? []).joined(separator: " ")
            return .thread(.new(
                agent: options.agent, folder: options.folder, model: options.model, mode: options.mode, name: options.name,
                text: message.isEmpty ? nil : message))
        case "send":
            guard let thread = rest.first, !thread.isEmpty, !text.isEmpty else {
                throw CommandLineToolError.usage("thread send needs an identifier and the text of the message.")
            }
            return .thread(.send(thread: thread, text: text))
        case "rename":
            guard let thread = rest.first, !thread.isEmpty else {
                throw CommandLineToolError.usage("thread rename needs an identifier, and the name to give.")
            }
            return .thread(.rename(thread: thread, name: text.isEmpty ? nil : text))
        case "read", "stop", "close":
            guard rest.count == 1, let thread = rest.first, !thread.isEmpty else {
                throw CommandLineToolError.usage("thread \(action) needs exactly one identifier.")
            }
            if action == "read" { return .thread(.read(thread: thread, printsJSON: options.printsJSON)) }
            return .thread(action == "stop" ? .stop(thread: thread) : .close(thread: thread))
        default:
            throw CommandLineToolError.usage("Unknown thread command \(action).")
        }
    }
}
