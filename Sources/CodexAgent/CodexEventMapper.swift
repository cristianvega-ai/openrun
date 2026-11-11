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

    /// The most items whose start the mapper keeps for an approval.
    static let itemLimit = 256

    /// The client identifiers of the user messages that went to Codex and
    /// that Codex has not echoed yet, oldest first.
    var pendingMessageIdentifiers: [String] = []
    /// Items that started and did not complete, for the approvals that
    /// name them, in the order of their start.
    var startedItems: [(identifier: String, item: JSONValue)] = []
    /// The turn that runs, from its start to its end.
    var activeTurn: String?
    /// The turn that the answer to `turn/start` named, until it starts or
    /// ends, and the last turn that ended.
    var requestedTurn: String?
    var lastEndedTurn: String?
    /// The tokens of the thread before the turn that runs, and now.
    var tokensBeforeTurn: TokenUsage?
    var tokensNow: TokenUsage?
    /// Items that OpenRun declined without the user, with the reason.
    var declineReasons: [String: ToolCallRefusal.Reason] = [:]

    mutating func events(method: String, parameters: JSONValue) -> [ConversationEventKind]? {
        let item = parameters["itemId"]?.string ?? ""
        // A command that a stop left as a background terminal goes on to
        // write and to end after its turn. In the chat it would show the
        // thread as busy, so it reaches only the log of the thread.
        if let turn = parameters["turnId"]?.string, turn != activeTurn, Self.isToolOutput(method, parameters) {
            return [.agentStatus(AgentStatus(kind: method, detail: "after the end of its turn"))]
        }
        switch method {
        case "turn/started": return turnStarted(parameters)
        case "turn/completed": return turnCompleted(parameters)
        case "thread/tokenUsage/updated": return tokenUsageUpdated(parameters)
        case "item/started": return itemStarted(parameters["item"] ?? .null)
        case "item/completed": return itemCompleted(parameters["item"] ?? .null)
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

    static func isToolOutput(_ method: String, _ parameters: JSONValue) -> Bool {
        method == "item/commandExecution/outputDelta" || method == "item/completed" && parameters["item"]?["type"]?.string == "commandExecution"
    }

    /// A short detail of a status, such as the new state of the thread.
    static func statusDetail(_ parameters: JSONValue) -> String? {
        if let status = parameters["status"] ?? parameters["thread"]?["status"] {
            let flags = (status["activeFlags"]?.array ?? []).compactMap(\.string)
            return ([status["type"]?.string ?? status.string].compactMap(\.self) + flags).joined(separator: " ")
        }
        return parameters["run"]?["status"]?.string ?? parameters["name"]?.string
    }
}
