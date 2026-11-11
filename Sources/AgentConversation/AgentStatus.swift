/// A line of a known kind that changes nothing that a chat shows, such as
/// the end of one block of a model's answer or the list of commands.
///
/// It is still an event, so the adapter keeps every line as it arrived.
public struct AgentStatus: Codable, Sendable, Hashable {
    /// The kind of line, such as `stream_event/message_stop`.
    public var kind: String
    /// A short detail, such as the new status.
    public var detail: String?

    public init(kind: String, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }
}
