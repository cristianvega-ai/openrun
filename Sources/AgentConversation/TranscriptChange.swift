/// The items that one event changed, so a view can update only those.
public struct TranscriptChange: Sendable, Hashable {
    /// New items, at the end of the transcript, in order.
    public var inserted: [String] = []
    /// Items that changed in place.
    public var updated: [String] = []
    /// The oldest items, which went to keep the transcript in its limits.
    public var removed: [String] = []

    public init() {}

    public var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && removed.isEmpty
    }
}
