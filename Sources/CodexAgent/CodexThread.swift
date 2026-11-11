import AgentConversation

/// An open Codex thread on its app-server.
///
/// Read `events` in a task of its own: while too many events wait, the
/// app-server reads no more output, for every thread of the account.
public struct CodexThread: Sendable {
    /// The identifier of the thread, which `resumeThread` takes.
    public let identifier: String
    /// The events of the thread, from its start to its close or the end of
    /// the app-server. Only one task may read them.
    public let events: AsyncStream<ConversationEvent>
    let server: CodexAppServer
    /// Runs after the close, so that a pool can end an idle server.
    let closed: (@Sendable () async -> Void)?

    /// Sends a user message, which starts a turn. Returns when Codex took
    /// the turn. The events of the turn follow.
    public func startTurn(_ turn: CodexTurn) async throws {
        try await server.startTurn(turn, thread: identifier)
    }

    /// Answers a permission request of the thread with the user's answer.
    /// Returns false when the request no longer waits, and then nothing
    /// goes to Codex.
    @discardableResult
    public func answerPermission(identifier: String, answer: CodexPermissionAnswer) async -> Bool {
        await server.answerPermission(identifier, answer: answer, thread: self.identifier)
    }

    /// Stops the thread: it declines the requests that wait, interrupts
    /// the turn, and ends the commands that still run. The next turn works
    /// as usual.
    @discardableResult
    public func stop() async -> CodexStop {
        await server.stop(thread: identifier)
    }

    /// A page of the earlier turns of the thread: the newest page without
    /// a cursor, and an older one with the cursor of the page before.
    public func historyPage(cursor: String? = nil, turnLimit: Int = 10) async throws -> CodexHistoryPage {
        try await server.historyPage(thread: identifier, cursor: cursor, turnLimit: turnLimit)
    }

    /// Ends the thread on the app-server. Its events end. The app-server
    /// stays for its other threads.
    public func close() async {
        await server.closeThread(identifier)
        await closed?()
    }
}
