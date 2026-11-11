/// The task of a sub-agent in a transcript.
public struct TaskItem: Codable, Sendable, Hashable {
    /// The start, when it has come. A message can come first.
    public var start: TaskStart?
    /// The newest messages inside the task, each cut to the detail limit.
    public var messages: [String]
    /// How many older messages went to keep the item small.
    public var removedMessageCount: Int
    /// Nil while the task runs.
    public var end: TaskEnd?

    public init(start: TaskStart?) {
        self.start = start
        messages = []
        removedMessageCount = 0
    }
}
