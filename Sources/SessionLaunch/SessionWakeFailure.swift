/// Why a wake request brought no socket path.
public enum SessionWakeFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// launchd knows no such Mach service: the app has not registered the
    /// launch agent.
    case notRegistered
    /// The request ended without an answer. The detail is the error text.
    case noAnswer(detail: String)
    /// The request received no answer before the time limit.
    case timedOut(limit: Duration)

    public var description: String {
        switch self {
        case .notRegistered:
            "The OpenRun session process is not registered with launchd. Open OpenRun once to register it."
        case .noAnswer(let detail):
            "The session process did not answer the request to start (\(detail))."
        case .timedOut(let limit):
            "The session process did not answer the request to start within \(limit.components.seconds) seconds. If the agent does not start after a rebuild, open OpenRun and choose File > Register Session Process Again."
        }
    }
}
