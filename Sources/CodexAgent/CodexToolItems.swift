import AgentConversation

/// The items that act for the agent: commands, file changes, and calls of
/// MCP tools, dynamic tools and the web search.
///
/// Codex has no tool names of the kind that Claude Code has. The type of
/// the item takes their place, such as `commandExecution`, and its input
/// holds what the user must see, such as the command and its folder.
extension CodexEventMapper {
    /// The most items that OpenRun declined without the user, kept for the
    /// reason of their refusal.
    static let declineLimit = 256

    func toolCallStarted(_ item: JSONValue, identifier: String, type: String) -> [ConversationEventKind] {
        let name = Self.toolName(item, type: type)
        var events: [ConversationEventKind] = [
            .toolCallStarted(ToolCallStart(identifier: identifier, name: name)),
            .toolCallInput(ToolCallInput(identifier: identifier, name: name, input: Self.toolInput(item, type: type))),
        ]
        if type == "fileChange" { events += CodexFileChanges.changes(of: item).map(ConversationEventKind.fileChange) }
        return events
    }

    mutating func toolCallCompleted(_ item: JSONValue, identifier: String, type: String) -> [ConversationEventKind] {
        var events: [ConversationEventKind] = type == "fileChange" ? CodexFileChanges.changes(of: item).map(ConversationEventKind.fileChange) : []
        let status = item["status"]?.string
        let reason = declineReasons.removeValue(forKey: identifier)
        if status == "declined" {
            let message = reason == .unanswered
                ? "No one answered the request in time, so OpenRun declined it." : "The user declined it in OpenRun."
            events.append(.toolCallRefused(ToolCallRefusal(
                identifier: identifier, toolName: Self.toolName(item, type: type), reason: reason ?? .user, message: message)))
            return events
        }
        let exitCode = item["exitCode"]?.integer
        let isError = status != "completed" || (exitCode ?? 0) != 0 || item["error"].map { $0 != .null } == true
        events.append(.toolCallResult(ToolCallResult(identifier: identifier, output: Self.toolOutput(item), isError: isError, exitCode: exitCode)))
        return events
    }

    /// Marks an item that OpenRun declined without the user, such as after
    /// the time limit, so its refusal says so.
    mutating func noteDecline(of identifier: String, reason: ToolCallRefusal.Reason) {
        if declineReasons.count >= Self.declineLimit { declineReasons.removeAll() }
        declineReasons[identifier] = reason
    }

    static func toolName(_ item: JSONValue, type: String) -> String {
        switch type {
        case "mcpToolCall": "mcp/\(item["server"]?.string ?? "")/\(item["tool"]?.string ?? "")"
        case "dynamicToolCall": item["tool"]?.string ?? type
        default: type
        }
    }

    static func toolInput(_ item: JSONValue, type: String) -> JSONValue {
        switch type {
        case "commandExecution": .object(["command": item["command"] ?? .null, "cwd": item["cwd"] ?? .null])
        case "fileChange": .object(["changes": .array(CodexFileChanges.changes(of: item).map { change in
            .object(["path": .string(change.path), "kind": .string(change.kind.rawValue)]) })])
        case "webSearch": .object(["query": item["query"] ?? .null])
        default: item["arguments"] ?? .null
        }
    }

    /// The text that the tool gave back: the output of a command, the text
    /// blocks of an MCP result, or the message of an error.
    static func toolOutput(_ item: JSONValue) -> String {
        if let output = item["aggregatedOutput"]?.string { return output }
        if let message = item["error"]?["message"]?.string { return message }
        let blocks = item["result"]?["content"]?.array ?? item["contentItems"]?.array ?? []
        return blocks.compactMap { $0["text"]?.string }.joined(separator: "\n")
    }
}
