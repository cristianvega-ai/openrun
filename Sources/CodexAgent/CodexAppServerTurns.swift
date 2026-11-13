import AgentConversation

/// The start of a turn.
extension CodexAppServer {
    /// The most messages that wait for Codex to take them.
    static let pendingMessageLimit = 64

    func startTurn(_ turn: CodexTurn, thread: String) async throws {
        try await beginTurn(turn, thread: thread).value
    }

    func beginTurn(_ turn: CodexTurn, thread: String) throws -> Task<Void, any Error> {
        guard threads[thread] != nil else { throw CodexRequestError.threadIsClosed }
        // The message shows at once. When Codex takes it, its item comes
        // with the same identifier, and the chat marks it as taken.
        threads[thread]?.mapper.pendingMessageIdentifiers.append(turn.messageIdentifier)
        if (threads[thread]?.mapper.pendingMessageIdentifiers.count ?? 0) > Self.pendingMessageLimit {
            threads[thread]?.mapper.pendingMessageIdentifiers.removeFirst()
        }
        emit([.userMessage(turn.userMessage)], line: nil, to: thread)
        threads[thread]?.startingTurnCount += 1
        return Task { try await self.finishTurnStart(turn, thread: thread) }
    }

    private func finishTurnStart(_ turn: CodexTurn, thread: String) async throws {
        defer {
            threads[thread]?.startingTurnCount -= 1
            if threads[thread]?.startingTurnCount == 0 { threads[thread]?.stopsTheStartingTurns = false }
        }
        do {
            let answer = try await request("turn/start", turn.parameters(thread: thread))
            guard let started = answer["turn"]?["id"]?.string else { return }
            threads[thread]?.mapper.noteRequestedTurn(started)
            if threads[thread]?.stopsTheStartingTurns == true {
                let parameters = JSONValue.object(["threadId": .string(thread), "turnId": .string(started)])
                _ = try? await request("turn/interrupt", parameters)
            }
        } catch {
            threads[thread]?.mapper.pendingMessageIdentifiers.removeAll { $0 == turn.messageIdentifier }
            throw error
        }
    }
}
