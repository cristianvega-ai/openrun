import AgentConversation

/// One app-server for each account, kept while a thread of the account is
/// open, and ended when none is. Many threads of an account share it.
public actor CodexAccountServers {
    typealias Start = @Sendable (_ accountFolder: String?) async throws -> CodexAppServer

    struct Entry {
        let server: Task<CodexAppServer, any Error>
        let generation: Int
        var threads: Set<String> = []
        /// Calls that use the server now, such as a thread start.
        var users = 0
    }

    let start: Start
    /// The servers by the `CODEX_HOME` folder of the account, or nil for
    /// the default account.
    var entries: [String?: Entry] = [:]
    var nextGeneration = 0

    init(start: @escaping Start) {
        self.start = start
    }

    /// The number of app-servers that run or start.
    public var serverCount: Int { entries.count }

    /// Runs `body` with the server of the account, which starts when the
    /// account has none. A thread that `body` opens keeps the server.
    func use<Result: Sendable>(
        _ account: String?, _ body: (CodexAppServer, _ generation: Int) async throws -> (Result, thread: String?)
    ) async throws -> Result {
        if let entry = entries[account], await (try? entry.server.value)?.hasEnded == true {
            entries[account] = nil
        }
        if entries[account] == nil {
            nextGeneration += 1
            entries[account] = Entry(server: Task { [start] in try await start(account) }, generation: nextGeneration)
        }
        guard let entry = entries[account] else { throw CodexRequestError.connectionEnded }
        entries[account]?.users += 1
        do {
            let (result, thread) = try await body(try await entry.server.value, entry.generation)
            if let thread, entries[account]?.generation == entry.generation { entries[account]?.threads.insert(thread) }
            await release(account, generation: entry.generation, thread: nil, user: true)
            return result
        } catch {
            await release(account, generation: entry.generation, thread: nil, user: true)
            throw error
        }
    }

    /// Ends a use or a thread. The server ends when nothing uses it.
    func release(_ account: String?, generation: Int, thread: String?, user: Bool) async {
        guard var entry = entries[account], entry.generation == generation else { return }
        if user { entry.users -= 1 }
        if let thread { entry.threads.remove(thread) }
        guard entry.users == 0, entry.threads.isEmpty else {
            entries[account] = entry
            return
        }
        entries[account] = nil
        if let server = try? await entry.server.value { await server.shutDown() }
    }
}
