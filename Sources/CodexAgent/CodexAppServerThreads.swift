import AgentConversation

/// The start, the resume and the close of threads.
extension CodexAppServer {
    /// Starts a new thread. Codex writes a trust entry for a new folder
    /// into its own configuration file.
    public func startThread(_ start: CodexThreadStart) async throws -> CodexThread {
        try await openThread(from: try await request("thread/start", .object(start.parameters)), method: "thread/start")
    }

    /// Resumes a thread that Codex keeps, by its identifier. Its earlier
    /// turns come from `CodexThread.historyPage`.
    public func resumeThread(identifier: String, _ start: CodexThreadStart) async throws -> CodexThread {
        guard threads[identifier] == nil else { throw CodexRequestError.threadIsOpen }
        var parameters = start.parameters
        parameters["threadId"] = .string(identifier)
        parameters["excludeTurns"] = .bool(true)
        return try await openThread(from: try await request("thread/resume", .object(parameters)), method: "thread/resume")
    }

    /// The number of open threads.
    public var openThreadCount: Int { threads.count }

    func openThread(from result: JSONValue, method: String) async throws -> CodexThread {
        guard let identifier = result["thread"]?["id"]?.string else { throw CodexRequestError.unexpectedAnswer(method: method) }
        guard threads[identifier] == nil else { throw CodexRequestError.threadIsOpen }
        let start = AgentStart(
            conversationIdentifier: identifier, model: result["model"]?.string, permissionMode: result["approvalPolicy"]?.string,
            agentVersion: result["thread"]?["cliVersion"]?.string, workingFolder: result["cwd"]?.string)
        let channel = await open(identifier, first: [.agentStarted(start)])
        return CodexThread(identifier: identifier, events: channel.stream, server: self, closed: nil)
    }

    func closeThread(_ identifier: String) async {
        await endApprovals(of: { $0 == identifier })
        guard let state = threads.removeValue(forKey: identifier) else { return }
        state.channel.finish()
        unsubscribe(identifier)
    }

    /// The most time that the answer to `thread/unsubscribe` may take.
    static let unsubscribeTimeLimit: Duration = .seconds(2)

    /// Tells Codex to send no more notifications of the thread here. Its
    /// answer has no use, so a close does not wait for it, even when the
    /// app-server answers nothing.
    func unsubscribe(_ thread: String) {
        let line = JSONValue.object(["threadId": .string(thread)])
        Task { _ = try? await connection.request("thread/unsubscribe", line, timeLimit: Self.unsubscribeTimeLimit) }
    }
}
