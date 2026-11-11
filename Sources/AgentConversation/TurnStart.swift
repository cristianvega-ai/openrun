/// The agent started to work on a user message.
public struct TurnStart: Codable, Sendable, Hashable {
    /// The message that started the turn, when the agent names it.
    public var userMessageIdentifier: String?

    public init(userMessageIdentifier: String? = nil) {
        self.userMessageIdentifier = userMessageIdentifier
    }
}
