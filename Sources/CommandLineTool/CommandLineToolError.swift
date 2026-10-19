import TerminalEmulation

/// Why a command did not finish. The error decides the exit code.
enum CommandLineToolError: Error, CustomStringConvertible {
    /// The user typed the command wrongly. Exit code 2.
    case usage(String)
    /// The command was fine and could not be done. Exit code 1.
    case failure(String)
    /// Like `failure`, with a heading and then one line for each entry of a
    /// list. The tool's own line breaks between them are kept when the error
    /// is printed, while the text of each line is escaped.
    case failureWithList(heading: String, lines: [String])

    var exitCode: Int32 {
        switch self {
        case .usage: 2
        case .failure, .failureWithList: 1
        }
    }

    var description: String {
        switch self {
        case .usage(let message), .failure(let message): message
        case .failureWithList(let heading, let lines): ([heading] + lines).joined(separator: "\n")
        }
    }

    /// The message for the terminal of the caller. It can hold text that a
    /// client chose, so each line is escaped on its own. The line breaks that
    /// separate the lines of a list are the tool's own and stay. A line break
    /// inside one line is client text and is escaped like the rest.
    var printableDescription: String {
        switch self {
        case .usage(let message), .failure(let message):
            PrintableText.escaping(message)
        case .failureWithList(let heading, let lines):
            ([heading] + lines).map(PrintableText.escaping).joined(separator: "\n")
        }
    }
}
