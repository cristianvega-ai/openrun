import AgentConversation
import Foundation

/// The threads and the readings of each account.
extension CodexAccountServers {
    public func startThread(account: String?, _ start: CodexThreadStart) async throws -> CodexThread {
        try await use(account) { server, generation in
            let thread = try await server.startThread(start)
            return (pooled(thread, account: account, generation: generation), thread.identifier)
        }
    }

    public func resumeThread(account: String?, identifier: String, _ start: CodexThreadStart) async throws -> CodexThread {
        try await use(account) { server, generation in
            let thread = try await server.resumeThread(identifier: identifier, start)
            return (pooled(thread, account: account, generation: generation), thread.identifier)
        }
    }

    /// Reads the account. Without an open thread, a server starts for the
    /// read and ends after it.
    public func readAccount(account: String?) async throws -> CodexAccount {
        try await use(account) { server, _ in (try await server.readAccount(), nil) }
    }

    public func readUsage(account: String?) async throws -> UsageReading {
        try await use(account) { server, _ in (try await server.readUsage(), nil) }
    }

    /// The processes of the app-servers that run. A program that one of
    /// them started works for an agent, and not for the user.
    public func processIdentifiers() async -> [pid_t] {
        var identifiers: [pid_t] = []
        for entry in entries.values {
            if let identifier = (try? await entry.server.value)?.processIdentifier { identifiers.append(identifier) }
        }
        return identifiers
    }

    /// Ends every server, such as when the session process ends.
    public func shutDown() async {
        let all = entries
        entries = [:]
        for entry in all.values {
            // A server that still starts gives up its handshake at once.
            entry.server.cancel()
            if let server = try? await entry.server.value { await server.shutDown() }
        }
    }

    /// The thread, whose close ends the server after its last thread.
    func pooled(_ thread: CodexThread, account: String?, generation: Int) -> CodexThread {
        CodexThread(identifier: thread.identifier, events: thread.events, server: thread.server) {
            await self.release(account, generation: generation, thread: thread.identifier, user: false)
        }
    }
}
