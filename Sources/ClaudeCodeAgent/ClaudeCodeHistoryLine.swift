import AgentConversation

/// Turns one line of the history file of Claude Code into the events that
/// a chat shows.
///
/// Only `user`, `assistant` and `system` lines that are not a side chain
/// give events. The other kinds, such as `api-request-blob` with the whole
/// system prompt or `session-owner` with the account, give none, and so do
/// kinds that this version does not know.
enum ClaudeCodeHistoryLine {
    static func events(_ line: JSONValue) -> [ConversationEventKind] {
        guard line["isSidechain"]?.bool != true else { return [] }
        let content = line["message"]?["content"] ?? .null
        switch line["type"]?.string {
        case "user":
            // Claude Code adds lines of its own, such as notes for the model.
            guard line["isMeta"]?.bool != true, line["isCompactSummary"]?.bool != true else { return [] }
            let results = (content.array ?? []).filter { $0["type"]?.string == "tool_result" }
            if !results.isEmpty {
                let details = results.count == 1 ? line["toolUseResult"] : nil
                return results.flatMap { ClaudeCodeContent.toolResultEvents($0, details: details) }
            }
            return [.userMessage(UserMessage(
                identifier: line["uuid"]?.string ?? "", text: ClaudeCodeContent.text(of: content),
                imageCount: ClaudeCodeContent.imageCount(of: content), isAccepted: true))]
        case "assistant":
            if line["isApiErrorMessage"]?.bool == true {
                return [.notice(Notice(level: .error, text: ClaudeCodeContent.text(of: content)))]
            }
            let message = line["message"]?["id"]?.string ?? line["uuid"]?.string ?? ""
            let blocks = content.array ?? []
            return blocks.enumerated().map { place, block in
                // The line gives the index of its block in the message.
                let index = blocks.count == 1 ? line["apiBlockIndex"]?.integer ?? place : place
                return ClaudeCodeContent.assistantEvent(block, itemIdentifier: "\(message):\(index)")
                    ?? .agentStatus(AgentStatus(kind: "assistant/" + (block["type"]?.string ?? "")))
            }
        case "system" where line["subtype"]?.string == "turn_duration":
            return [.turnEnded(TurnEnd(outcome: .done, durationMilliseconds: line["durationMs"]?.integer))]
        default:
            return []
        }
    }
}
