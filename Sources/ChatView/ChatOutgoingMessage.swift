import AgentConversation

/// A message that the user sends from the composer.
public struct ChatOutgoingMessage: Equatable, Hashable, Sendable {
    public var text: String
    /// Pasted or dropped images, each a PNG, JPEG, GIF or WebP file within
    /// the size limit of the composer.
    public var images: [MessageImage]

    public init(text: String, images: [MessageImage] = []) {
        self.text = text
        self.images = images
    }
}
