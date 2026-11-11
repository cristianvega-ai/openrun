import AgentConversation
import Foundation

/// What Claude Code gives the `PermissionRequest` hook on its standard
/// input when a tool call needs the user.
///
/// The request has no tool call identifier. `ClaudeCodeToolCallMatcher`
/// finds the call in the output by its tool name and input.
public struct ClaudeCodePermissionHookRequest: Sendable, Hashable {
    public var conversationIdentifier: String
    /// The history file of the conversation.
    public var transcriptPath: String?
    public var workingFolder: String?
    public var permissionMode: String?
    public var toolName: String
    public var toolInput: JSONValue

    public init(decoding data: Data) throws {
        guard let request = try? JSONValue(decoding: data), request["hook_event_name"]?.string == "PermissionRequest",
              let conversation = request["session_id"]?.string, let toolName = request["tool_name"]?.string
        else { throw ClaudeCodePermissionHookError.invalidRequest }
        conversationIdentifier = conversation
        transcriptPath = request["transcript_path"]?.string
        workingFolder = request["cwd"]?.string
        permissionMode = request["permission_mode"]?.string
        self.toolName = toolName
        toolInput = request["tool_input"] ?? .null
    }

    /// The event of this request, with the identifier that OpenRun gives it.
    public func permissionRequest(identifier: String, toolCallIdentifier: String?) -> PermissionRequest {
        PermissionRequest(identifier: identifier, toolName: toolName, input: toolInput, toolCallIdentifier: toolCallIdentifier)
    }
}

public enum ClaudeCodePermissionHookError: Error, Equatable {
    /// The standard input of the hook was not a permission request.
    case invalidRequest
}
