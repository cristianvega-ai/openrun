/// Why a wake request brought no socket path.
public enum SessionWakeFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// launchd knows no such Mach service: the app has not registered the
    /// launch agent.
    case notRegistered
    /// The request ended without an answer. The detail is the error text.
    case noAnswer(detail: String)
    /// launchd did not start the session process in time. A registration
    /// whose program has a new code signature fails this way, because
    /// launchd refuses the program and the request waits for ever.
    case timedOut(limit: Duration)

    public var description: String {
        switch self {
        case .notRegistered:
            "The OpenRun session process is not registered with launchd. Open OpenRun once to register it."
        case .noAnswer(let detail):
            "The session process did not answer the request to start (\(detail))."
        case .timedOut(let limit):
            "launchd did not start the session process within \(limit.components.seconds) seconds. Open OpenRun to register it again."
        }
    }
}
