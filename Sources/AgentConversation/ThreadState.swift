/// The state of a thread that the list of threads shows.
public enum ThreadState: String, Codable, Sendable {
    /// No turn runs, and none has ended since the thread opened, or the
    /// user stopped the last one.
    case idle
    /// The agent works on a turn.
    case inProgress
    /// A permission request waits for the user.
    case needsUser
    /// The agent finished its last turn.
    case finishedTurn
    /// The last turn failed, or the agent's process ended by itself with
    /// an error.
    case failed
}
