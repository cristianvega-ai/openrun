import AgentProgram
import Darwin
import Testing
@testable import CodexAgent

/// A server that nobody holds any more cannot leave its app-server behind,
/// also when a thread is open and nothing shut the server down.
@Suite struct CodexReleaseTests {
    @Test func aDroppedServerEndsItsAppServer() async throws {
        var server: CodexAppServer? = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start"]))
        let program = try await processIdentifierOfAThread(in: #require(server))
        server = nil
        try await expectEnd(of: program)
    }

    @Test func droppedServersOfTheAccountsEndTheirAppServer() async throws {
        var servers: CodexAccountServers? = CodexAccountServers(launch: CodexFakeServer.launch(["thread-start"]))
        var thread = try await servers?.startThread(account: "/config/codex", CodexThreadStart(folder: "/work/project"))
        let program = try await processIdentifier(of: #require(thread?.server))
        servers = nil
        // The thread holds its server, so the app-server stays.
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(program, 0) == 0)
        thread = nil
        try await expectEnd(of: program)
    }

    /// Opens a thread and drops it without a close.
    func processIdentifierOfAThread(in server: CodexAppServer) async throws -> pid_t {
        _ = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        return try await processIdentifier(of: server)
    }

    func processIdentifier(of server: CodexAppServer) async throws -> pid_t {
        let transport = await server.connection.transport
        return try #require(transport as? AgentProgram).processIdentifier
    }

    /// Waits up to 5 seconds until the process is gone and reaped.
    func expectEnd(of process: pid_t) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while kill(process, 0) == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let isGone = kill(process, 0) == -1
        #expect(isGone)
        if !isGone { kill(process, SIGKILL) }
    }
}
