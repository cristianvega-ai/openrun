/// A message of the user to the agent.
///
/// The session process reports it when it sends the message, and the agent
/// reports it again when it takes the message. Both carry the same
/// identifier, so the second one only marks the first as taken.
public struct UserMessage: Codable, Sendable, Hashable {
    public var identifier: String
    public var text: String
    /// The number of images that came with the text.
    public var imageCount: Int
    /// Whether the agent has taken the message.
    public var isAccepted: Bool

    public init(identifier: String, text: String, imageCount: Int = 0, isAccepted: Bool) {
        self.identifier = identifier
        self.text = text
        self.imageCount = imageCount
        self.isAccepted = isAccepted
    }
}
