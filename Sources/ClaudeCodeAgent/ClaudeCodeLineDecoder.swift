import AgentConversation

/// Turns one line of the stream-json output of Claude Code into events.
///
/// A line that means nothing to a chat, such as `message_stop`, gives a
/// status event, so that each line reaches the log of the thread. A line of
/// a kind that this version does not know gives nil.
struct ClaudeCodeLineDecoder: Sendable {
    /// The message that streams now, from its `message_start`.
    var streamMessage: String?
    /// The tool call of each block of the message that streams now.
    var streamToolCalls: [Int: String] = [:]
    /// The message of the last `assistant` line, and how many of its blocks
    /// came. Each line holds one block, in the order of the blocks.
    var assistantMessage: String?
    var assistantBlockCount = 0
    /// The tasks that run a sub-agent, as opposed to a command.
    var agentTasks: Set<String> = []

    mutating func decode(_ line: JSONValue) -> [ConversationEventKind]? {
        guard let type = line["type"]?.string else { return nil }
        switch type {
        case "system": return systemEvents(line)
        case "assistant": return assistantEvents(line)
        case "user": return userEvents(line)
        case "result": return [.turnEnded(Self.turnEnd(line))]
        case "rate_limit_event": return [.usage(ClaudeCodeUsage.reading(from: line["rate_limit_info"] ?? .null))]
        case "command_lifecycle":
            let state = line["state"]?.string
            if state == "started" { return [.turnStarted(TurnStart(userMessageIdentifier: line["command_uuid"]?.string))] }
            return [.agentStatus(AgentStatus(kind: type, detail: state))]
        case "control_request", "control_response", "keep_alive":
            return [.agentStatus(AgentStatus(kind: type, detail: line["request"]?["subtype"]?.string))]
        default: return nil
        }
    }

    private mutating func assistantEvents(_ line: JSONValue) -> [ConversationEventKind]? {
        let message = line["message"] ?? .null
        let blocks = message["content"]?.array ?? []
        if line["is_api_error_message"]?.bool == true || line["error"] != nil {
            return [.notice(Notice(level: .error, text: ClaudeCodeContent.text(of: message["content"] ?? .null)))]
        }
        if let task = line["parent_tool_use_id"]?.string {
            return blocks.map { .taskMessage(TaskMessage(toolCallIdentifier: task, text: ClaudeCodeContent.text(of: .array([$0])))) }
        }
        let identifier = message["id"]?.string ?? ""
        if identifier != assistantMessage {
            assistantMessage = identifier
            assistantBlockCount = 0
        }
        var events: [ConversationEventKind] = []
        for block in blocks {
            guard let event = ClaudeCodeContent.assistantEvent(block, itemIdentifier: "\(identifier):\(assistantBlockCount)") else { return nil }
            events.append(event)
            assistantBlockCount += 1
        }
        return events.isEmpty ? [.agentStatus(AgentStatus(kind: "assistant"))] : events
    }

    private func userEvents(_ line: JSONValue) -> [ConversationEventKind]? {
        let content = line["message"]?["content"] ?? .null
        let text = ClaudeCodeContent.text(of: content)
        if let task = line["parent_tool_use_id"]?.string {
            return [.taskMessage(TaskMessage(toolCallIdentifier: task, text: text))]
        }
        if line["isReplay"]?.bool == true {
            return [.userMessage(UserMessage(
                identifier: line["uuid"]?.string ?? "", text: text,
                imageCount: ClaudeCodeContent.imageCount(of: content), isAccepted: true))]
        }
        let results = (content.array ?? []).filter { $0["type"]?.string == "tool_result" }
        guard !results.isEmpty else {
            // Claude Code adds a user line of its own, such as after a stop.
            return [.notice(Notice(level: .information, text: text))]
        }
        let details = results.count == 1 ? line["tool_use_result"] : nil
        return results.flatMap { ClaudeCodeContent.toolResultEvents($0, details: details) }
    }

    static func turnEnd(_ line: JSONValue) -> TurnEnd {
        let reason = line["terminal_reason"]?.string ?? ""
        let succeeded = line["subtype"]?.string == "success" && line["is_error"]?.bool != true
        let outcome: TurnEnd.Outcome = reason.hasPrefix("aborted") ? .stopped : succeeded ? .done : .failed
        let errors = (line["errors"]?.array ?? []).compactMap(\.string)
        let errorText = outcome != .failed ? nil : errors.isEmpty ? line["result"]?.string : errors.joined(separator: "\n")
        let usage = line["usage"].map { usage in
            TokenUsage(
                inputTokens: usage["input_tokens"]?.integer ?? 0, outputTokens: usage["output_tokens"]?.integer ?? 0,
                cacheReadInputTokens: usage["cache_read_input_tokens"]?.integer ?? 0,
                cacheCreationInputTokens: usage["cache_creation_input_tokens"]?.integer ?? 0)
        }
        return TurnEnd(
            outcome: outcome, errorText: errorText, usage: usage, durationMilliseconds: line["duration_ms"]?.integer,
            serviceDurationMilliseconds: line["duration_api_ms"]?.integer, estimatedCostInDollars: line["total_cost_usd"]?.number)
    }
}
