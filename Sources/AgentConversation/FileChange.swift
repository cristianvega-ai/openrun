/// A change of one file that a tool call of the agent made.
public struct FileChange: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case added, modified, deleted
    }

    /// Unique within the conversation.
    public var identifier: String
    /// The tool call that made the change, when there is one.
    public var toolCallIdentifier: String?
    /// The path of the file, as the agent gives it.
    public var path: String
    public var kind: Kind
    /// The change as a unified diff, cut to a limit.
    public var diff: String

    public init(identifier: String, toolCallIdentifier: String? = nil, path: String, kind: Kind, diff: String) {
        self.identifier = identifier
        self.toolCallIdentifier = toolCallIdentifier
        self.path = path
        self.kind = kind
        self.diff = diff
    }
}
