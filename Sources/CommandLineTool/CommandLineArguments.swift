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
        var helpRequested = false
        var folder: String?
        var positional: [String] = []

        var remaining = words[...]
        while let word = remaining.popFirst() {
            switch word {
            case "--socket":
                socketPath = try Self.value(of: word, from: &remaining)
            case "--folder":
                folder = try Self.value(of: word, from: &remaining)
            case "--enter":
                pressEnter = true
            case "--scrollback":
                includeScrollback = true
            case "--help":
                helpRequested = true
                remaining.removeAll()
            default:
                if word.hasPrefix("--socket=") {
                    socketPath = String(word.dropFirst("--socket=".count))
                } else if word.hasPrefix("--folder=") {
                    folder = String(word.dropFirst("--folder=".count))
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

        let command: ToolCommand
        switch name {
        case "list":
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, afterSeparator)
            guard rest.isEmpty else { throw CommandLineToolError.usage("list takes no arguments.") }
            command = .list
        case "help":
            guard rest.isEmpty else { throw CommandLineToolError.usage("help takes no arguments.") }
            try Self.requireNoOptions(name, folder, pressEnter, includeScrollback, afterSeparator)
            command = .help
        default:
            throw CommandLineToolError.usage("Unknown command \(name).")
        }
        self.init(socketPath: socketPath, command: command)
    }

    private static func value(of option: String, from remaining: inout ArraySlice<String>) throws -> String {
        guard let value = remaining.popFirst() else {
            throw CommandLineToolError.usage("\(option) needs a value.")
        }
        return value
    }

    private static let commandNames: Set<String> = ["new", "list", "attach", "read", "send", "kill", "help"]

    private static func requireNoOptions(_ name: String, _ folder: String?, _ pressEnter: Bool, _ includeScrollback: Bool, _ afterSeparator: [String]?) throws {
        if folder != nil { throw CommandLineToolError.usage("--folder does not belong to \(name). It works with new.") }
        if pressEnter { throw CommandLineToolError.usage("--enter does not belong to \(name). It works with send.") }
        if includeScrollback { throw CommandLineToolError.usage("--scrollback does not belong to \(name). It works with read.") }
        if afterSeparator != nil { throw CommandLineToolError.usage("\(name) takes nothing after --.") }
    }
}
