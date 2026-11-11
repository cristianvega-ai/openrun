import AgentConversation

/// The `stream_event` lines of Claude Code's output, which carry the
/// pieces of a message as the service sends them.
extension ClaudeCodeLineDecoder {
    mutating func streamEvents(_ line: JSONValue) -> [ConversationEventKind]? {
        let event = line["event"] ?? .null
        guard let type = event["type"]?.string else { return nil }
        let status = [ConversationEventKind.agentStatus(AgentStatus(kind: "stream_event/" + type))]
        // The pieces of a sub-agent's message show in its task, from the
        // complete lines.
        guard line["parent_tool_use_id"]?.string == nil else { return status }
        if type == "message_start" {
            streamMessage = event["message"]?["id"]?.string ?? line["api_message_id"]?.string
            streamToolCalls = [:]
            return status
        }
        let message = line["api_message_id"]?.string ?? streamMessage ?? ""
        guard let index = event["index"]?.integer else { return status }
        let item = "\(message):\(index)"
        switch type {
        case "content_block_start":
            let block = event["content_block"] ?? .null
            switch block["type"]?.string {
            case "thinking", "redacted_thinking":
                return [.thinking(Thinking(itemIdentifier: item, isComplete: false))]
            case "tool_use":
                guard let identifier = block["id"]?.string else { return status }
                // A stream without `message_start` must not grow the table.
                if streamToolCalls.count >= 1_024 { streamToolCalls = [:] }
                streamToolCalls[index] = identifier
                return [.toolCallStarted(ToolCallStart(identifier: identifier, name: block["name"]?.string ?? ""))]
            default:
                return status
            }
        case "content_block_delta":
            let delta = event["delta"] ?? .null
            switch delta["type"]?.string {
            case "text_delta":
                return [.agentTextDelta(AgentTextDelta(itemIdentifier: item, text: delta["text"]?.string ?? ""))]
            case "thinking_delta":
                return [.thinking(Thinking(itemIdentifier: item, estimatedTokens: delta["estimated_tokens"]?.integer, isComplete: false))]
            case "input_json_delta":
                guard let identifier = streamToolCalls[index] else { return status }
                return [.toolCallInputDelta(ToolCallInputDelta(identifier: identifier, partialInput: delta["partial_json"]?.string ?? ""))]
            default:
                return status
            }
        default:
            return status
        }
    }
}
