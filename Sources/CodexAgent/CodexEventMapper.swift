import AgentConversation

/// Turns the notifications of one Codex thread into conversation events.
///
/// A notification that means nothing to a chat, such as the start of an
/// MCP server, gives a status event, so that each line reaches the log of
/// the thread. A method that this version does not know gives nil.
struct CodexEventMapper: Sendable {
    /// Methods that change nothing that a chat shows.
    static let statusMethods: Set<String> = [
        "thread/started", "thread/status/changed", "thread/goal/updated", "thread/goal/cleared", "thread/name/updated",
        "thread/settings/updated", "thread/closed", "thread/archived", "thread/unarchived", "thread/readState/changed",
        "thread/queue/changed", "thread/environment/connected", "thread/environment/disconnected", "skills/changed",
        "turn/diff/updated", "turn/plan/updated", "turn/moderationMetadata", "item/plan/delta", "item/fileChange/outputDelta",
        "item/fileChange/patchUpdated", "item/commandExecution/terminalInteraction", "item/mcpToolCall/progress",
        "hook/started", "hook/completed", "mcpServer/startupStatus/updated", "serverRequest/resolved", "account/updated",
        "remoteControl/status/changed", "app/list/updated", "model/verification", "model/safetyBuffering/updated",
        "item/autoApprovalReview/started", "item/autoApprovalReview/completed",
    ]

    mutating func events(method: String, parameters: JSONValue) -> [ConversationEventKind]? {
        let item = parameters["itemId"]?.string ?? ""
        switch method {
        case "item/agentMessage/delta":
            return [.agentTextDelta(AgentTextDelta(itemIdentifier: item, text: parameters["delta"]?.string ?? ""))]
        case "item/commandExecution/outputDelta":
            return [.toolCallOutput(ToolCallOutput(identifier: item, text: parameters["delta"]?.string ?? ""))]
        case "item/reasoning/summaryTextDelta", "item/reasoning/summaryPartAdded", "item/reasoning/textDelta":
            return [.thinking(Thinking(itemIdentifier: item.isEmpty ? nil : item, isComplete: false))]
        case "account/rateLimits/updated":
            return [.usage(CodexUsage.reading(from: parameters["rateLimits"] ?? .null))]
        case "error":
            let error = parameters["error"] ?? .null
            let text = error["message"]?.string ?? ""
            if parameters["willRetry"]?.bool == true {
                return [.notice(Notice(level: .warning, text: "Codex tries the request again: \(text)"))]
            }
            return [.notice(Notice(level: .error, text: text))]
        case "warning", "configWarning", "guardianWarning", "windows/worldWritableWarning":
            return [.notice(Notice(level: .warning, text: parameters["message"]?.string ?? parameters["summary"]?.string ?? ""))]
        case "deprecationNotice":
            return [.notice(Notice(level: .warning, text: parameters["summary"]?.string ?? ""))]
        case "model/rerouted":
            return [.notice(Notice(level: .information, text: "Codex moved the turn to the model \(parameters["toModel"]?.string ?? "")."))]
        case "thread/compacted":
            return [.notice(Notice(level: .information, text: "Codex compacted the conversation."))]
        default:
            guard Self.statusMethods.contains(method) else { return nil }
            return [.agentStatus(AgentStatus(kind: method, detail: Self.statusDetail(parameters)))]
        }
    }

    /// A short detail of a status, such as the new state of the thread.
    static func statusDetail(_ parameters: JSONValue) -> String? {
        if let status = parameters["status"] {
            let flags = (status["activeFlags"]?.array ?? []).compactMap(\.string)
            return ([status["type"]?.string ?? status.string].compactMap(\.self) + flags).joined(separator: " ")
        }
        return parameters["run"]?["status"]?.string ?? parameters["name"]?.string
    }
}
