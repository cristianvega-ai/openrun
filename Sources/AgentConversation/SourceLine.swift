/// The line of the agent's output that an event came from.
///
/// Each adapter keeps every event as it arrives (proposal 4 of 2026-11-10),
/// so a later version can read again what this one did not understand. A
/// line can be many megabytes, so only its start stays.
public struct SourceLine: Codable, Sendable, Hashable {
    /// The most bytes of a line that an event keeps.
    public static let byteLimit = 16 * 1024

    /// The start of the line, at most `byteLimit` bytes, without its line end.
    public var text: String
    /// The length of the whole line in bytes.
    public var byteCount: Int

    public init(text: String, byteCount: Int) {
        self.text = text
        self.byteCount = byteCount
    }

    /// Keeps the start of `bytes`, one line without its line end.
    public init(bytes: some Collection<UInt8>) {
        text = BoundedText.prefix(of: bytes, byteLimit: Self.byteLimit)
        byteCount = bytes.count
    }

    /// Whether `text` holds the whole line.
    public var isComplete: Bool {
        text.utf8.count == byteCount
    }
}
