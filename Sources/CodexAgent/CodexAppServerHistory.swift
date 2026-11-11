import AgentConversation

/// The history of a thread, newest page first.
extension CodexAppServer {
    func historyPage(thread: String, cursor: String?, turnLimit: Int) async throws -> CodexHistoryPage {
        var parameters: [String: JSONValue] = [
            "threadId": .string(thread), "limit": .number(Double(max(1, turnLimit))), "itemsView": .string("full"),
        ]
        if let cursor { parameters["cursor"] = .string(cursor) }
        let answer = try await request("thread/turns/list", .object(parameters))
        guard let turns = answer["data"]?.array else { throw CodexRequestError.unexpectedAnswer(method: "thread/turns/list") }
        return CodexHistoryPage(events: CodexHistory.events(of: turns).map { ConversationEvent($0) }, olderCursor: answer["nextCursor"]?.string)
    }
}
