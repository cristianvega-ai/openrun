import AgentConversation

/// The items of a turn: messages, reasoning, commands, file changes and
/// other tool calls. Each has a start and a completion.
extension CodexEventMapper {
    mutating func itemStarted(_ item: JSONValue) -> [ConversationEventKind]? {
        let identifier = item["id"]?.string ?? ""
        let type = item["type"]?.string ?? ""
        switch type {
        case "userMessage":
            let message = userMessage(item, pendingIdentifier: pendingMessageIdentifiers.first)
            if let place = pendingMessageIdentifiers.firstIndex(of: message.identifier) { pendingMessageIdentifiers.remove(at: place) }
            return [.userMessage(message)]
        case "agentMessage":
            return [.agentStatus(AgentStatus(kind: "item/started", detail: type))]
        case "reasoning":
            return [.thinking(Thinking(itemIdentifier: identifier, isComplete: false))]
        case "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch":
            return toolCallStarted(item, identifier: identifier, type: type)
        case "contextCompaction":
            return [.notice(Notice(level: .information, text: "Codex compacts the conversation."))]
        default:
            return nil
        }
    }

    mutating func itemCompleted(_ item: JSONValue) -> [ConversationEventKind]? {
        let identifier = item["id"]?.string ?? ""
        let type = item["type"]?.string ?? ""
        switch type {
        case "userMessage", "contextCompaction":
            return [.agentStatus(AgentStatus(kind: "item/completed", detail: type))]
        case "agentMessage":
            return [.agentText(AgentText(itemIdentifier: identifier, text: item["text"]?.string ?? ""))]
        case "reasoning":
            return [.thinking(Thinking(itemIdentifier: identifier, isComplete: true))]
        case "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch":
            return toolCallCompleted(item, identifier: identifier, type: type)
        default:
            return nil
        }
    }

    /// The user message of an item. Codex gives back the identifier that
    /// OpenRun sent as `clientId`. When it does not, the oldest message
    /// that waits takes the item, so the chat does not show it twice.
    func userMessage(_ item: JSONValue, pendingIdentifier: String?) -> UserMessage {
        let content = item["content"]?.array ?? []
        let text = content.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined(separator: "\n")
        let images = content.count { ["image", "localImage"].contains($0["type"]?.string ?? "") }
        let identifier = item["clientId"]?.string ?? pendingIdentifier ?? item["id"]?.string ?? ""
        return UserMessage(identifier: identifier, text: text, imageCount: images, isAccepted: true)
    }
}
