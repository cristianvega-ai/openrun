/// A line of the agent's output that this version cannot read.
///
/// A new version of an agent can add kinds of lines at any time. The chat
/// shows such a line as a plain row (proposal 4), and the stream goes on.
public struct UnknownLine: Codable, Sendable, Hashable {
    public enum Reason: String, Codable, Sendable {
        /// The line is not a JSON object.
        case notJSON
        /// The line is JSON of a kind that this version does not know.
        case unknownKind
        /// The line was longer than the limit, so it was not read.
        case tooLong
        /// The output ended in the middle of the line.
        case cutShort
    }

    public var reason: Reason
    /// The kind that the line names, when it names one.
    public var kind: String?
    /// The start of the line.
    public var text: String
    /// The length of the whole line in bytes.
    public var byteCount: Int

    public init(reason: Reason, kind: String? = nil, text: String, byteCount: Int) {
        self.reason = reason
        self.kind = kind
        self.text = text
        self.byteCount = byteCount
    }
}
