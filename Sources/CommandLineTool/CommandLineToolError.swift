import SessionConnection
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

    /// The words of the tool for an error of the connection. They name the
    /// commands that help, and put each candidate of an unclear identifier
    /// on a line of its own.
    init(_ error: SessionConnectionError) {
        switch error {
        case .noSessionProcess(let socketPath):
            self = .failure("No session process answers on \(socketPath). Start one with openrun-session, or choose a socket with --socket.")
        case .protocolFailure:
            self = .failure(error.description)
        case .emptyIdentifier:
            self = .usage(error.description)
        case .noMatchingSession(let typed):
            self = .failure("No session has an identifier that starts with \(typed). Run 'openrun list' to see the sessions.")
        case .ambiguousIdentifier(let typed, let candidates):
            self = .failureWithList(
                heading: "More than one session starts with \(typed). Type more characters.",
                lines: candidates.map { "  \($0.identifierText)  \($0.folder)" }
            )
        }
    }

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
