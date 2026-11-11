/// One item that a chat shows.
public struct TranscriptItem: Codable, Sendable, Hashable {
    /// Stable while the item lives, so a view can update the item in place
    /// while its text streams. The same events give the same identifiers.
    public var identifier: String
    public var content: TranscriptItemContent

    public init(identifier: String, content: TranscriptItemContent) {
        self.identifier = identifier
        self.content = content
    }
}
