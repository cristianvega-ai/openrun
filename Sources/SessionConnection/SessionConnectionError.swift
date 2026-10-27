import SessionProtocol

/// Why a step of the conversation with the session process failed.
///
/// The text names no command or option of a client, so each client can add
/// its own words for what the user does next.
public enum SessionConnectionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The typed identifier is empty.
    case emptyIdentifier
    /// No session has an identifier that starts with the typed text.
    case noMatchingSession(typed: String)
    /// More than one session has an identifier that starts with the typed
    /// text. The candidates are those sessions.
    case ambiguousIdentifier(typed: String, candidates: [SessionSummary])

    public var description: String {
        switch self {
        case .emptyIdentifier:
            "The identifier is empty."
        case .noMatchingSession(let typed):
            "No session has an identifier that starts with \(typed)."
        case .ambiguousIdentifier(let typed, let candidates):
            "More than one session starts with \(typed): \(candidates.map(\.identifierText).joined(separator: ", "))."
        }
    }
}
