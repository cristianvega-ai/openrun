import SessionProtocol

/// Finds the session that a typed identifier means. People type the start of
/// an identifier, as with git commits, so the start must be unique.
enum SessionIdentifierMatch {
    static func find(_ typed: String, in summaries: [SessionSummary]) throws -> SessionSummary {
        let wanted = typed.lowercased()
        guard !wanted.isEmpty else { throw CommandLineToolError.usage("The identifier is empty.") }

        let matches = summaries.filter { $0.identifierText.hasPrefix(wanted) }
        if let exact = matches.first(where: { $0.identifierText == wanted }) { return exact }
        switch matches.count {
        case 0:
            throw CommandLineToolError.failure("No session has an identifier that starts with \(typed). Run 'openrun list' to see the sessions.")
        case 1:
            return matches[0]
        default:
            throw CommandLineToolError.failureWithList(
                heading: "More than one session starts with \(typed). Type more characters.",
                lines: matches.map { "  \($0.identifierText)  \($0.folder)" }
            )
        }
    }
}
