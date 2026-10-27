import SessionProtocol

/// Why a step of the conversation with the session process failed.
///
/// The text names no command or option of a client, so each client can add
/// its own words for what the user does next.
public enum SessionConnectionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No program listens on the socket: it does not exist, or nothing
    /// accepts connections on it.
    case noSessionProcess(socketPath: String)
    /// The socket or the protocol failed, such as a system call, a frame or
    /// the version.
    case protocolFailure(SessionProtocolError)
    /// The session process closed the connection before it answered.
    case connectionClosed
    /// The session process could not do the request. The failure says why.
    case requestFailed(SessionFailure)
    /// The answer does not fit the request that the text names.
    case unexpectedAnswer(request: String)
    /// The typed identifier is empty.
    case emptyIdentifier
    /// No session has an identifier that starts with the typed text.
    case noMatchingSession(typed: String)
    /// More than one session has an identifier that starts with the typed
    /// text. The candidates are those sessions.
    case ambiguousIdentifier(typed: String, candidates: [SessionSummary])

    public var description: String {
        switch self {
        case .noSessionProcess(let socketPath):
            "No session process answers on \(socketPath)."
        case .protocolFailure(let error):
            error.description
        case .connectionClosed:
            "The session process closed the connection."
        case .requestFailed(let failure):
            failure.message
        case .unexpectedAnswer(let request):
            "The session process gave an unexpected answer to the \(request) request."
        case .emptyIdentifier:
            "The identifier is empty."
        case .noMatchingSession(let typed):
            "No session has an identifier that starts with \(typed)."
        case .ambiguousIdentifier(let typed, let candidates):
            "More than one session starts with \(typed): \(candidates.map(\.identifierText).joined(separator: ", "))."
        }
    }

    /// Runs one step of the protocol. A `SessionProtocolError` becomes
    /// `protocolFailure`, so a client meets one type of error.
    static func wrapping<Result>(_ step: () throws -> Result) throws -> Result {
        do {
            return try step()
        } catch let error as SessionProtocolError {
            throw SessionConnectionError.protocolFailure(error)
        }
    }
}
