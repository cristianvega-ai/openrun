import AgentConversation
import Foundation
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

    @Test func identityDoesNotWaitForStartup() async throws {
        let gate = IdentityStartupGate()
        let servers = CodexAccountServers { _ in
            await gate.wait()
            return try await CodexServerHarness().server
        }
        let opening = Task { try await servers.use(nil) { server, _ in (server, "thread") } }
        while await !gate.entered { await Task.yield() }
        let identity = await servers.processIdentity()
        #expect(identity.hasUnidentifiedProcess)
        await gate.release()
        _ = try await opening.value
        #expect(await !servers.processIdentity().hasUnidentifiedProcess)
        await servers.shutDown()
    }

    @Test func shutdownKeepsUnresolvedIdentityUntilStartupEnds() async throws {
        let gate = IdentityStartupGate()
        let servers = CodexAccountServers { account in
            if account == nil {
                await gate.wait()
                throw CancellationError()
            }
            return try await CodexServerHarness().server
        }
        let opening = Task { try await servers.use(nil) { server, _ in (server, "thread") } }
        while await !gate.entered { await Task.yield() }
        let shutdown = Task { await servers.shutDown() }
        while await servers.serverCount != 0 { await Task.yield() }
        // No server starts after the shutdown began.
        await #expect(throws: CodexRequestError.connectionEnded) { try await servers.use("second") { server, _ in (server, "second") } }
        #expect(await servers.processIdentity().hasUnidentifiedProcess)
        await gate.release()
        _ = try? await opening.value
        await shutdown.value
        #expect(await !servers.processIdentity().hasUnidentifiedProcess)
    }

    @Test func noServerStartsAfterTheShutdown() async throws {
        let starts = Mutex(0)
        let servers = CodexAccountServers { _ in
            starts.withLock { $0 += 1 }
            return try await CodexServerHarness().server
        }
        await servers.shutDown()
        await #expect(throws: CodexRequestError.connectionEnded) { try await servers.use(nil) { server, _ in (server, "late") } }
        let count = await servers.serverCount
        #expect(starts.withLock { $0 } == 0 && count == 0)
    }

    @Test func aReadWithoutThreadStartsAServerForTheReadAlone() async throws {
        let servers = CodexAccountServers { _ in
            let harness = try await CodexServerHarness()
            // A failed play leaves the read without an answer, and the
            // expectations below then fail.
            Task { try? await harness.play("usage") }
            return harness.server
        }
        let account = try await servers.readAccount(account: "/config/a")
        #expect(account.plan == "plus")
        #expect(await servers.serverCount == 0)
    }
}

private actor IdentityStartupGate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
