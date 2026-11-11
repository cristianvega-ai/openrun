/// The agent asks the user before a tool call.
///
/// For Claude Code the session process makes this event from the request
/// that reaches OpenRun's permission hook. That request names no tool
/// call, so `toolCallIdentifier` is the call that its tool and input match,
/// when one does.
public struct PermissionRequest: Codable, Sendable, Hashable {
    /// Unique within the conversation. `PermissionEnd` uses it.
    public var identifier: String
    public var toolName: String
    public var input: JSONValue
    public var toolCallIdentifier: String?

    public init(identifier: String, toolName: String, input: JSONValue, toolCallIdentifier: String? = nil) {
        self.identifier = identifier
        self.toolName = toolName
        self.input = input
        self.toolCallIdentifier = toolCallIdentifier
    }
}
