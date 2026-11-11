import AgentConversation
import Testing
@testable import CodexAgent

/// A close and a shutdown against a fake app-server that answers nothing,
/// reads nothing and ignores SIGTERM.
@Suite struct CodexEndToEndCloseTests {
    func time(_ body: () async throws -> Void) async rethrows -> Duration {
        let start = ContinuousClock.now
        try await body()
        return ContinuousClock.now - start
    }

    /// Whether the server learns its end within two seconds. The reader
    /// learns it a moment after the end of the process.
    func hasEnded(_ server: CodexAppServer) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while await !server.hasEnded, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        return await server.hasEnded
    }

    @Test func aCloseAndAShutdownAreQuick() async throws {
        let server = try await CodexAppServer.start(CodexFakeServer.launch(["thread-start", "deaf"]))
        let thread = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        #expect(await time { await thread.close() } < .seconds(1))
        #expect(await time { await server.shutDown() } < .seconds(5))
        #expect(try await hasEnded(server))
    }

    @Test func theCloseOfTheLastThreadOfAnAccountIsQuick() async throws {
        let servers = CodexAccountServers(launch: CodexFakeServer.launch(["thread-start", "deaf"]))
        let thread = try await servers.startThread(account: "/config/codex", CodexThreadStart(folder: "/work/project"))
        #expect(await time { await thread.close() } < .seconds(5))
        #expect(await servers.serverCount == 0)
        #expect(try await hasEnded(thread.server))
    }
}
