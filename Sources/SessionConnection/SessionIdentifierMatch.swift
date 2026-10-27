import SessionProtocol

/// Finds the session that a typed identifier means. People type the start of
/// an identifier, as with git commits, so the start must be unique.
public enum SessionIdentifierMatch {
    /// Throws `SessionConnectionError` when no session or more than one matches.
    public static func find(_ typed: String, in summaries: [SessionSummary]) throws -> SessionSummary {
        let wanted = typed.lowercased()
        guard !wanted.isEmpty else { throw SessionConnectionError.emptyIdentifier }

        let matches = summaries.filter { $0.identifierText.hasPrefix(wanted) }
        if let exact = matches.first(where: { $0.identifierText == wanted }) { return exact }
        switch matches.count {
        case 0:
            throw SessionConnectionError.noMatchingSession(typed: typed)
        case 1:
            return matches[0]
        default:
            throw SessionConnectionError.ambiguousIdentifier(typed: typed, candidates: matches)
        }
    }
}
