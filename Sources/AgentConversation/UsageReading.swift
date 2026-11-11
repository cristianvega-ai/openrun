/// A reading of an account's usage, which an agent gives after a request.
///
/// Claude Code gives it once after the first request of a process, and
/// again when the figures change, so a reading can be old. The session
/// process keeps the time when it came.
public struct UsageReading: Codable, Sendable, Hashable {
    public var windows: [UsageWindow]
    /// The agent's word for the state of the whole account.
    public var status: String?
    /// The fields of the reading that this version does not read, kept
    /// whole, because the agents add fields that no document lists.
    public var otherFields: [String: JSONValue]

    public init(windows: [UsageWindow], status: String? = nil, otherFields: [String: JSONValue] = [:]) {
        self.windows = windows
        self.status = status
        self.otherFields = otherFields
    }
}
