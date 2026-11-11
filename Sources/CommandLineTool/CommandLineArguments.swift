/// The words after `openrun`, split into a command and the options that every
/// command shares.
struct CommandLineArguments: Equatable {
    var socketPath: String?
    var command: ToolCommand

    init(socketPath: String?, command: ToolCommand) {
        self.socketPath = socketPath
        self.command = command
    }

    /// Reads the arguments. Throws a usage error for anything unclear.
    init(_ arguments: [String]) throws {
        var words = arguments
        // Everything after "--" belongs to the command. In `new` it is the
        // program to run, and in `send` it is the text to type.
        let separator = words.firstIndex(of: "--")
        let afterSeparator = separator.map { Array(words[($0 + 1)...]) }
        if let separator { words.removeSubrange(separator...) }

        var socketPath: String?
        var pressEnter = false
        var includeScrollback = false
        var printsJSON = false
        var helpRequested = false
        var folder: String?
        var session: String?
        var projectName: String?
        var (model, mode): (String?, String?)
        var positional: [String] = []

        var remaining = words[...]
        while let word = remaining.popFirst() {
            switch word {
            case "--socket":
                socketPath = try Self.value(of: word, from: &remaining)
            case "--folder":
                folder = try Self.value(of: word, from: &remaining)
            case "--session":
                session = try Self.value(of: word, from: &remaining)
            case "--name":
                projectName = try Self.value(of: word, from: &remaining)
            case "--model":
                model = try Self.value(of: word, from: &remaining)
            case "--mode":
                mode = try Self.value(of: word, from: &remaining)
            case "--enter":
                pressEnter = true
            case "--scrollback":
                includeScrollback = true
            case "--json":
                printsJSON = true
            case "--help":
                helpRequested = true
                remaining.removeAll()
            default:
                if word.hasPrefix("--socket=") {
                    socketPath = String(word.dropFirst("--socket=".count))
                } else if word.hasPrefix("--folder=") {
                    folder = String(word.dropFirst("--folder=".count))
                } else if word.hasPrefix("--session=") {
                    session = String(word.dropFirst("--session=".count))
                } else if word.hasPrefix("--name=") {
                    projectName = String(word.dropFirst("--name=".count))
                } else if word.hasPrefix("-") && word.count > 1 {
                    throw CommandLineToolError.usage("Unknown option \(word).")
                } else {
                    positional.append(word)
                }
            }
        }

        if helpRequested {
            // The help option belongs to a real command, as in `read abc --help`.
            // It does not rescue a word that is no command.
            if let first = positional.first, !Self.commandNames.contains(first) {
                throw CommandLineToolError.usage("Unknown command \(first).")
            }
            self.init(socketPath: socketPath, command: .help)
            return
        }
        guard let name = positional.first else {
            throw CommandLineToolError.usage("Missing command.")
        }
        let rest = Array(positional.dropFirst())
        if printsJSON, name != "list", name != "project", name != "thread" {
            throw CommandLineToolError.usage("--json does not belong to \(name). It works with list, project list, thread list and thread read.")
        }
        if projectName != nil, name != "project", name != "thread" {
            throw CommandLineToolError.usage("--name does not belong to \(name). It works with project add and thread new.")
        }
        if model != nil || mode != nil, name != "thread" {
            throw CommandLineToolError.usage("\(model != nil ? "--model" : "--mode") does not belong to \(name). It works with thread new.")
        }
        if session != nil, name != "notify" { throw CommandLineToolError.usage("--session does not belong to \(name). It works with notify.") }

        func allow(_ flag: String, used: Bool, in commands: String) throws {
            if used { throw CommandLineToolError.usage("\(flag) does not belong to \(name). It works with \(commands).") }
        }

        let command: ToolCommand
        switch name {
        case "new":
            try allow("--enter", used: pressEnter, in: "send")
            try allow("--scrollback", used: includeScrollback, in: "read")
            guard rest.isEmpty else { throw CommandLineToolError.usage("new takes no identifier or text. Put the program after --.") }
            if let afterSeparator, afterSeparator.isEmpty {
                throw CommandLineToolError.usage("Put a program after --.")
            }
            command = .new(folder: folder, program: afterSeparator ?? [])
        case "list":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, afterSeparator)
            guard rest.isEmpty else { throw CommandLineToolError.usage("list takes no arguments.") }
            command = .list(printsJSON: printsJSON)
        case "attach":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, afterSeparator)
            command = .attach(identifier: try Self.single(rest, name: name))
        case "read":
            try allow("--enter", used: pressEnter, in: "send")
            try Self.requireNoOptions(name, folder, false, false, afterSeparator)
            command = .read(identifier: try Self.single(rest, name: name), includeScrollback: includeScrollback)
        case "send":
            try allow("--scrollback", used: includeScrollback, in: "read")
            try Self.requireNoOptions(name, folder, false, false, nil)
            guard let identifier = rest.first else { throw CommandLineToolError.usage("send needs an identifier and text.") }
            try Self.requireIdentifier(identifier)
            let text = (Array(rest.dropFirst()) + (afterSeparator ?? [])).joined(separator: " ")
            guard !text.isEmpty || pressEnter else { throw CommandLineToolError.usage("send needs text to type, or --enter.") }
            command = .send(identifier: identifier, text: text, pressEnter: pressEnter)
        case "kill":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, afterSeparator)
            command = .kill(identifier: try Self.single(rest, name: name))
        case "rename":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, nil)
            guard let identifier = rest.first else { throw CommandLineToolError.usage("rename needs an identifier, and the name to give.") }
            try Self.requireIdentifier(identifier)
            let newName = (Array(rest.dropFirst()) + (afterSeparator ?? [])).joined(separator: " ")
            command = .rename(identifier: identifier, name: newName.isEmpty ? nil : newName)
        case "notify":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, nil)
            if let session { try Self.requireIdentifier(session) }
            let text = (rest + (afterSeparator ?? [])).joined(separator: " ")
            guard !text.isEmpty else { throw CommandLineToolError.usage("notify needs the text of the alert.") }
            command = .notify(identifier: session, text: text)
        case "project":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, nil)
            command = try Self.projectCommand(rest + (afterSeparator ?? []), printsJSON: printsJSON, name: projectName)
        case "settings":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, nil)
            command = try Self.settingsCommand(rest + (afterSeparator ?? []))
        case "thread":
            try Self.requireNoOptions(name, nil, pressEnter, includeScrollback, nil)
            let options = ThreadOptions(folder: folder, model: model, mode: mode, name: projectName, printsJSON: printsJSON)
            command = try Self.threadCommand(rest, afterSeparator: afterSeparator, options: options)
        case "help":
            guard rest.isEmpty else { throw CommandLineToolError.usage("help takes no arguments.") }
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, afterSeparator)
            command = .help
        default:
            throw CommandLineToolError.usage("Unknown command \(name).")
        }
        self.init(socketPath: socketPath, command: command)
    }

    /// The words after `project`: the action, and what it acts on.
    private static func projectCommand(_ words: [String], printsJSON: Bool, name: String?) throws -> ToolCommand {
        guard let action = words.first else { throw CommandLineToolError.usage("project needs list, add, remove or rename.") }
        let rest = words.dropFirst()
        if printsJSON, action != "list" {
            throw CommandLineToolError.usage("--json does not belong to project \(action). It works with list and project list.")
        }
        if name != nil, action != "add" { throw CommandLineToolError.usage("--name does not belong to project \(action). It works with project add.") }
        switch action {
        case "list":
            guard rest.isEmpty else { throw CommandLineToolError.usage("project list takes no arguments.") }
            return .projectList(printsJSON: printsJSON)
        case "add":
            guard rest.count == 1, let folder = rest.first, !folder.isEmpty else { throw CommandLineToolError.usage("project add needs one folder.") }
            return .projectChange(.add(folder: folder, name: name))
        case "remove":
            guard rest.count == 1, let project = rest.first, !project.isEmpty else {
                throw CommandLineToolError.usage("project remove needs one identifier or folder.")
            }
            return .projectChange(.remove(project: project))
        case "rename":
            guard let project = rest.first, !project.isEmpty else { throw CommandLineToolError.usage("project rename needs an identifier or a folder, and the name to give.") }
            let newName = rest.dropFirst().joined(separator: " ")
            return .projectChange(.rename(project: project, name: newName.isEmpty ? nil : newName))
        default:
            throw CommandLineToolError.usage("Unknown project command \(action).")
        }
    }

    /// The words after `settings`. The value of `set` is the rest of the
    /// words, joined by spaces, as the text of `send`.
    private static func settingsCommand(_ words: [String]) throws -> ToolCommand {
        let rest = Array(words.dropFirst())
        switch words.first {
        case "list":
            guard rest.isEmpty else { throw CommandLineToolError.usage("settings list takes no arguments.") }
            return .settings(.list)
        case "get":
            guard rest.count == 1, let name = rest.first else { throw CommandLineToolError.usage("settings get needs one setting name.") }
            return .settings(.get(name: name))
        case "set":
            guard rest.count >= 2 else { throw CommandLineToolError.usage("settings set needs a setting name and a value.") }
            return .settings(.set(name: rest[0], text: rest.dropFirst().joined(separator: " ")))
        case let action?:
            throw CommandLineToolError.usage("Unknown settings command \(action).")
        case nil:
            throw CommandLineToolError.usage("settings needs list, get or set.")
        }
    }

    private static func value(of option: String, from remaining: inout ArraySlice<String>) throws -> String {
        guard let value = remaining.popFirst() else {
            throw CommandLineToolError.usage("\(option) needs a value.")
        }
        return value
    }

    private static func single(_ words: [String], name: String) throws -> String {
        guard words.count == 1, let word = words.first else {
            throw CommandLineToolError.usage("\(name) needs exactly one identifier.")
        }
        try requireIdentifier(word)
        return word
    }

    /// An empty identifier matches every session. Refuse it here, before any
    /// connection, so it is a usage error with or without a session process.
    private static func requireIdentifier(_ word: String) throws {
        if word.isEmpty { throw CommandLineToolError.usage("The session identifier is empty.") }
    }

    private static let commandNames: Set<String> = ["new", "list", "attach", "read", "send", "kill", "rename", "notify", "project", "settings", "thread", "help"]

    /// Whether the command is `notify`, also when the arguments are wrong.
    static func namesNotify(_ arguments: [String]) -> Bool {
        var words = arguments.prefix { $0 != "--" }[...]
        while let word = words.popFirst() {
            if ["--socket", "--folder", "--session", "--name", "--model", "--mode"].contains(word) { _ = words.popFirst(); continue }
            if !word.hasPrefix("-") { return word == "notify" }
        }
        return false
    }

    private static func requireNoOptions(_ name: String, _ folder: String?, _ pressEnter: Bool, _ includeScrollback: Bool, _ afterSeparator: [String]?) throws {
        if folder != nil { throw CommandLineToolError.usage("--folder does not belong to \(name). It works with new.") }
        if pressEnter { throw CommandLineToolError.usage("--enter does not belong to \(name). It works with send.") }
        if includeScrollback { throw CommandLineToolError.usage("--scrollback does not belong to \(name). It works with read.") }
        if afterSeparator != nil { throw CommandLineToolError.usage("\(name) takes nothing after --.") }
    }
}
