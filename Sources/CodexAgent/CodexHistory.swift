import AgentConversation

/// The earlier turns of a thread as the same events as a live turn.
enum CodexHistory {
    static let stoppedTurnText = "Codex keeps only the user's message of a stopped turn. The answer before the stop is not in the history."

    /// The events of turns that Codex gives newest first, oldest first.
    static func events(of turns: [JSONValue]) -> [ConversationEventKind] {
        var mapper = CodexEventMapper()
        var events: [ConversationEventKind] = []
        for turn in turns.reversed() {
            events.append(.turnStarted(TurnStart()))
            let items = turn["items"]?.array ?? []
            for item in items {
                for method in ["item/started", "item/completed"] {
                    let kinds = mapper.events(method: method, parameters: .object(["item": item])) ?? []
                    events += kinds.filter { if case .agentStatus = $0 { false } else { true } }
                }
            }
            // The turn that runs now has no end yet.
            guard turn["status"]?.string != "inProgress" else { continue }
            let end = CodexEventMapper.turnEnd(turn)
            if end.outcome == .stopped, !items.contains(where: { $0["type"]?.string == "agentMessage" }) {
                events.append(.notice(Notice(level: .information, text: stoppedTurnText)))
            }
            events.append(.turnEnded(end))
        }
        return events
    }
}
