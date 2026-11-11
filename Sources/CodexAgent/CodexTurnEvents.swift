import AgentConversation

/// The start and the end of a turn, and the tokens that it used.
extension CodexEventMapper {
    mutating func turnStarted(_ parameters: JSONValue) -> [ConversationEventKind] {
        activeTurn = parameters["turn"]?["id"]?.string
        tokensBeforeTurn = tokensNow
        return [.turnStarted(TurnStart())]
    }

    mutating func turnCompleted(_ parameters: JSONValue) -> [ConversationEventKind] {
        let turn = parameters["turn"] ?? .null
        if turn["id"]?.string == activeTurn { activeTurn = nil }
        var end = Self.turnEnd(turn)
        // A turn that made no request, such as one with an unknown model,
        // gives no new total.
        if let now = tokensNow, now != tokensBeforeTurn { end.usage = Self.difference(now, tokensBeforeTurn) }
        tokensBeforeTurn = tokensNow
        var events: [ConversationEventKind] = [.turnEnded(end)]
        // The model has no place for the kind of the error, such as
        // `usageLimitExceeded`, so it comes as a status beside the end.
        if let kind = Self.errorKind(turn["error"]) {
            events.append(.agentStatus(AgentStatus(kind: "turn/error", detail: kind)))
        }
        return events
    }

    /// The end of a turn from its status and error, without the tokens.
    static func turnEnd(_ turn: JSONValue) -> TurnEnd {
        let error = turn["error"]?["message"]?.string
        let duration = turn["durationMs"]?.integer
        switch turn["status"]?.string {
        case "completed": return TurnEnd(outcome: .done, durationMilliseconds: duration)
        case "interrupted": return TurnEnd(outcome: .stopped, durationMilliseconds: duration)
        case "failed": return TurnEnd(outcome: .failed, errorText: error, durationMilliseconds: duration)
        case let status:
            let text = error ?? "The turn ended with the status \(status ?? "none")."
            return TurnEnd(outcome: .failed, errorText: text, durationMilliseconds: duration)
        }
    }

    /// The kind of an error: a word, or the name of the one member of an
    /// object, such as `httpConnectionFailed`.
    static func errorKind(_ error: JSONValue?) -> String? {
        guard let information = error?["codexErrorInfo"] else { return nil }
        return information.string ?? (information.object?.keys.count == 1 ? information.object?.keys.first : nil)
    }

    mutating func tokenUsageUpdated(_ parameters: JSONValue) -> [ConversationEventKind] {
        let usage = parameters["tokenUsage"] ?? .null
        let total = usage["total"] ?? .null
        let cached = total["cachedInputTokens"]?.integer ?? 0
        // Codex counts the input from the cache in the input. The model
        // counts it apart, as Claude Code does.
        tokensNow = TokenUsage(
            inputTokens: max(0, (total["inputTokens"]?.integer ?? 0) - cached), outputTokens: total["outputTokens"]?.integer ?? 0,
            cacheReadInputTokens: cached, cacheCreationInputTokens: total["cacheWriteInputTokens"]?.integer ?? 0)
        let window = usage["modelContextWindow"]?.integer.map { " of \($0)" } ?? ""
        let detail = (usage["last"]?["totalTokens"]?.integer).map { "\($0) tokens in the context\(window)" }
        return [.agentStatus(AgentStatus(kind: "thread/tokenUsage/updated", detail: detail))]
    }

    /// The tokens between two totals of a thread, never below zero.
    static func difference(_ now: TokenUsage, _ before: TokenUsage?) -> TokenUsage {
        guard let before else { return now }
        return TokenUsage(
            inputTokens: max(0, now.inputTokens - before.inputTokens), outputTokens: max(0, now.outputTokens - before.outputTokens),
            cacheReadInputTokens: max(0, now.cacheReadInputTokens - before.cacheReadInputTokens),
            cacheCreationInputTokens: max(0, now.cacheCreationInputTokens - before.cacheCreationInputTokens))
    }
}
