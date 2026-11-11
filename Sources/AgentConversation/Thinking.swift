/// The agent thinks before it answers.
///
/// The agents give only that thinking happens and an estimate of its
/// length, not its text.
public struct Thinking: Codable, Sendable, Hashable {
    /// The part of the answer that holds the thinking, when it is known.
    public var itemIdentifier: String?
    /// The agent's estimate of the tokens of thinking so far.
    public var estimatedTokens: Int?
    /// Whether this part of the thinking has ended.
    public var isComplete: Bool

    public init(itemIdentifier: String? = nil, estimatedTokens: Int? = nil, isComplete: Bool) {
        self.itemIdentifier = itemIdentifier
        self.estimatedTokens = estimatedTokens
        self.isComplete = isComplete
    }
}
