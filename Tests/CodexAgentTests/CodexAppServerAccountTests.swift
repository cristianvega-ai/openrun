import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerAccountTests {
    @Test func theAccountAndItsUsageNeedNoThread() async throws {
        let harness = try await CodexServerHarness()
        async let played = harness.play("usage")
        let account = try await harness.server.readAccount()
        let usage = try await harness.server.readUsage()
        _ = try await played
        #expect(account == CodexAccount(kind: "chatgpt", plan: "plus", emailAddress: "person@example.com"))
        #expect(!account.description.contains("person"))
        #expect(!String(reflecting: account).contains("person"))
        #expect(usage.windows.map(\.name) == ["seven_day"])
        #expect(usage.windows.first?.usedFraction == 0.04)
    }

    @Test func anAccountWithoutSignInSaysSo() {
        let account = CodexAccount(answer: .object(["account": .null, "requiresOpenaiAuth": .bool(true)]))
        #expect(account == CodexAccount(needsSignIn: true))
    }
}
