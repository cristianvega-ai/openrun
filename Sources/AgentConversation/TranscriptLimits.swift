/// The limits that keep the memory of a transcript bounded.
///
/// Text from an agent or a tool is untrusted, and a tool can print
/// gigabytes. When the items pass a limit, the oldest ones go first, and
/// the transcript counts them, so a view can say that earlier items exist.
public struct TranscriptLimits: Sendable, Hashable {
    /// The most items that the transcript keeps.
    public var itemLimit: Int
    /// The most bytes of text in all items together.
    public var byteLimit: Int
    /// The most bytes of the text of one message.
    public var messageByteLimit: Int
    /// The most bytes of one detail: the input or output of a tool call,
    /// a diff, a notice, or an unknown line.
    public var detailByteLimit: Int

    public init(
        itemLimit: Int = 5_000, byteLimit: Int = 8 * 1024 * 1024,
        messageByteLimit: Int = 1024 * 1024, detailByteLimit: Int = 256 * 1024
    ) {
        self.itemLimit = max(1, itemLimit)
        self.byteLimit = byteLimit
        self.messageByteLimit = messageByteLimit
        self.detailByteLimit = detailByteLimit
    }
}
