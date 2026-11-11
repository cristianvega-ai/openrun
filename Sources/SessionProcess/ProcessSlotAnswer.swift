/// The answer to a thread that wants to start the process of its agent.
enum ProcessSlotAnswer: Sendable, Equatable {
    case granted
    /// Every slot is taken by an agent that works. The thread is in line.
    case waits(limit: Int)
}
