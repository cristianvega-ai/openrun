import SessionConnection
import SessionProtocol
import UntrustedText

/// `openrun list`: one line per session, with tabs between the columns so
/// that a script can split them even when a folder contains spaces. With
/// `--json`, every fact of each session as JSON (see `ListedSession`).
///
/// A client chose the folder and the arguments. A tab or a new line inside
/// them would forge a column or a line, and an escape sequence would drive
/// the terminal of whoever runs `list`, so every field is escaped.
struct ListCommand {
    var printsJSON = false

    func run(location: SocketLocation) throws -> String {
        let summaries = try SessionClient(location: location).summaries()
        // JSON escapes every control character, so a field cannot forge a line.
        if printsJSON { return try ListedSession.document(of: summaries) }
        return summaries
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
