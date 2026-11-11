import AgentConversation
import Synchronization
import Testing
@testable import CodexAgent

@Suite struct CodexAccountServersTests {
    final class Starts: Sendable {
        let accounts = Mutex<[String?]>([])
    }

    let starts = Starts()

    func pool() -> CodexAccountServers {
        CodexAccountServers { [starts] account in
            starts.accounts.withLock { $0.append(account) }
            return try await CodexServerHarness().server
        }
    }

    @Test func aServerEndsAfterItsLastUseAndAThreadKeepsIt() async throws {
        let servers = pool()
        let first = try await servers.use("/config/a") { server, _ in (server, nil) }
        #expect(await servers.serverCount == 0)
        while await !first.hasEnded { try await Task.sleep(for: .milliseconds(10)) }
        _ = try await servers.use("/config/a") { server, _ in (server, "thread") }
        _ = try await servers.use("/config/a") { server, _ in (server, "second") }
        _ = try await servers.use(nil) { server, _ in (server, "default") }
        #expect(await servers.serverCount == 2)
        #expect(starts.accounts.withLock { $0 } == ["/config/a", "/config/a", nil])
    }

    @Test func aReadWithoutThreadStartsAServerForTheReadAlone() async throws {
        let servers = CodexAccountServers { _ in
            let harness = try await CodexServerHarness()
            Task { try await harness.play("usage") }
            return harness.server
        }
        let account = try await servers.readAccount(account: "/config/a")
        #expect(account.plan == "plus")
        #expect(await servers.serverCount == 0)
    }
}
