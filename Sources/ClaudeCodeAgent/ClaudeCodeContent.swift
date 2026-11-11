import AgentConversation

/// The blocks of a message of Claude Code, which its output and its
/// history file share: text, thinking, tool calls and their results.
enum ClaudeCodeContent {
    /// The event of one block of the agent's message, or nil for a block
    /// of a kind that this version does not know.
    static func assistantEvent(_ block: JSONValue, itemIdentifier: String) -> ConversationEventKind? {
        switch block["type"]?.string {
        case "text":
            return .agentText(AgentText(itemIdentifier: itemIdentifier, text: block["text"]?.string ?? ""))
        case "thinking", "redacted_thinking":
            return .thinking(Thinking(itemIdentifier: itemIdentifier, isComplete: true))
        case "tool_use":
            guard let identifier = block["id"]?.string else { return nil }
            return .toolCallInput(ToolCallInput(
                identifier: identifier, name: block["name"]?.string ?? "", input: block["input"] ?? .null))
        default:
            return nil
        }
    }

    /// The events of a tool result block. `details` is the structured
    /// result that Claude Code adds beside the message, such as the patch
    /// of an edit.
    static func toolResultEvents(_ block: JSONValue, details: JSONValue?) -> [ConversationEventKind] {
        guard let identifier = block["tool_use_id"]?.string else { return [] }
        let output = text(of: block["content"] ?? .null)
        var events: [ConversationEventKind] = [.toolCallResult(ToolCallResult(
            identifier: identifier, output: output, isError: block["is_error"]?.bool ?? false))]
        if let details, let change = fileChange(toolCallIdentifier: identifier, details: details) {
            events.append(.fileChange(change))
        }
        return events
    }

    /// The text of content that is a string or a list of blocks. Other
    /// blocks, such as an image, add a short note in brackets.
    static func text(of content: JSONValue) -> String {
        if let text = content.string { return text }
        let parts = (content.array ?? []).map { block in
            block["type"]?.string == "text" ? block["text"]?.string ?? "" : "[\(block["type"]?.string ?? "block")]"
        }
        return parts.joined(separator: "\n")
    }

    /// The number of image blocks in content.
    static func imageCount(of content: JSONValue) -> Int {
        (content.array ?? []).count { $0["type"]?.string == "image" }
    }

    /// The change of a file that an Edit or a Write call made, as a
    /// unified diff, or nil for the result of another tool.
    static func fileChange(toolCallIdentifier: String, details: JSONValue) -> FileChange? {
        guard let path = details["filePath"]?.string else { return nil }
        if let hunks = details["structuredPatch"]?.array, !hunks.isEmpty {
            let diff = hunks.map { hunk in
                let header = "@@ -\(number(hunk["oldStart"])),\(number(hunk["oldLines"]))"
                    + " +\(number(hunk["newStart"])),\(number(hunk["newLines"])) @@"
                return ([header] + (hunk["lines"]?.array ?? []).map { $0.string ?? "" }).joined(separator: "\n")
            }
            let kind: FileChange.Kind = details["type"]?.string == "create" ? .added : .modified
            return FileChange(identifier: toolCallIdentifier, toolCallIdentifier: toolCallIdentifier, path: path, kind: kind, diff: diff.joined(separator: "\n"))
        }
        guard details["type"]?.string == "create", let content = details["content"]?.string else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let added = (content.hasSuffix("\n") ? lines.dropLast() : lines[...]).map { "+" + $0 }
        let diff = (["@@ -0,0 +1,\(added.count) @@"] + added).joined(separator: "\n")
        return FileChange(identifier: toolCallIdentifier, toolCallIdentifier: toolCallIdentifier, path: path, kind: .added, diff: diff)
    }

    private static func number(_ value: JSONValue?) -> Int {
        value?.integer ?? 0
    }
}
