/// A request to the Codex app-server did not get a good answer.
public enum CodexRequestError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The app-server refused the request. The message is from Codex and
    /// can name a thread or a folder, so it is for display, not for a log.
    case refused(code: Int, message: String)
    /// No answer came in the time limit.
    case timedOut(method: String)
    /// The app-server ended, or its pipe closed, before the answer.
    case connectionEnded
    /// The answer did not have the form that the method gives.
    case unexpectedAnswer(method: String)

    public var description: String {
        switch self {
        case .refused(let code, let message): "Codex refused the request (\(code)): \(message)"
        case .timedOut(let method): "Codex gave no answer to \(method) in the time limit."
        case .connectionEnded: "The Codex app-server ended before it answered."
        case .unexpectedAnswer(let method): "Codex gave an answer to \(method) that OpenRun cannot read."
        }
    }
}
