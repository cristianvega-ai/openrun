/// The tokens that one turn used.
public struct TokenUsage: Codable, Sendable, Hashable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// Input tokens that the model read from its cache.
    public var cacheReadInputTokens: Int
    /// Input tokens that the model wrote to its cache.
    public var cacheCreationInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int = 0, cacheCreationInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }
}
