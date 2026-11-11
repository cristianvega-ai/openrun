import AgentConversation

/// The start of threads.
extension CodexAppServer {
    /// Starts a new thread. Codex writes a trust entry for a new folder
    /// into its own configuration file.
    public func startThread(_ start: CodexThreadStart) async throws -> CodexThread {
        try await openThread(from: try await request("thread/start", .object(start.parameters)), method: "thread/start")
    }

    /// The number of open threads.
    public var openThreadCount: Int { threads.count }

    func openThread(from result: JSONValue, method: String) async throws -> CodexThread {
        guard let identifier = result["thread"]?["id"]?.string else { throw CodexRequestError.unexpectedAnswer(method: method) }
        let start = AgentStart(
            conversationIdentifier: identifier, model: result["model"]?.string, permissionMode: result["approvalPolicy"]?.string,
            agentVersion: result["thread"]?["cliVersion"]?.string, workingFolder: result["cwd"]?.string)
        let channel = await open(identifier, first: [.agentStarted(start)])
        return CodexThread(identifier: identifier, events: channel.stream, server: self)
    }
}
