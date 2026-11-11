/// A request to a thread was refused. Nothing changed.
enum ThreadRunnerError: Error, Equatable, CustomStringConvertible {
    case tooManyWaitingMessages(limit: Int)
    case threadIsClosed

    var description: String {
        switch self {
        case .tooManyWaitingMessages(let limit): "The thread already holds \(limit) messages that wait for the agent. Send the message again later."
        case .threadIsClosed: "The thread is closed."
        }
    }
}
