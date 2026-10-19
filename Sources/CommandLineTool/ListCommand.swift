import SessionProtocol
import TerminalEmulation

/// `openrun list`: one line per session, with tabs between the columns so
/// that a script can split them even when a folder contains spaces.
///
/// A client chose the folder and the arguments. A tab or a new line inside
/// them would forge a column or a line, and an escape sequence would drive
/// the terminal of whoever runs `list`, so every field is escaped.
struct ListCommand {
    func run(location: SocketLocation) throws -> String {
        try SessionClient(location: location).summaries()
            .map { summary in
                let command = summary.command.map(PrintableText.escaping).joined(separator: " ")
                return [
                    PrintableText.escaping(summary.identifierText),
                    PrintableText.escaping(summary.folder),
                    command,
                ].joined(separator: "\t") + "\n"
            }
            .joined()
    }
}
