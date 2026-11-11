import UntrustedText

/// One entry of the new-session button: a name to show, and the command
/// that the new session runs.
public struct NewSessionCommand: Hashable, Sendable {
    public let name: String
    /// What an interactive login shell runs with `exec`, so the command
    /// gets the user's `PATH`. An empty command line starts the login shell
    /// itself.
    public let commandLine: String

    public static let nameLengthLimit = 50
    public static let commandLineLengthLimit = 1000
    /// More entries than this do not fit in the menu of the button.
    public static let countLimit = 20

    /// The login shell, Claude Code and Codex (decision of 2026-11-10).
    public static let defaults = [
        NewSessionCommand(name: "Shell", commandLine: ""),
        NewSessionCommand(name: "Claude Code", commandLine: "claude"),
        NewSessionCommand(name: "Codex", commandLine: "codex"),
    ]

    public init(name: String, commandLine: String) {
        self.name = name
        self.commandLine = commandLine
    }

    /// Whether the settings can hold this entry: a name of 1 to 50
    /// characters and a command line of at most 1000, both plain as
    /// `PlainName` checks. A new line in a command line would end the
    /// command that the shell reads and start another.
    var isValid: Bool {
        PlainName.isValid(name, lengthLimit: Self.nameLengthLimit)
            && PlainName.isValid(commandLine, lengthLimit: Self.commandLineLengthLimit, allowsEmpty: true)
    }
}
