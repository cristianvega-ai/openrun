import AgentConversation
import Testing
@testable import CodexAgent

/// A thread whose caller reads nothing holds back no answer of the account.
@Suite struct CodexStalledThreadTests {
    let options = CodexServerOptions(answerTimeLimit: .seconds(3), eventLimit: 5)

    func delta(_ index: Int) -> String {
        #"{"method":"item/agentMessage/delta","params":{"threadId":"stalled","itemId":"m","delta":"\#(index)"}}"#
    }

    /// Runs `call`, answers its request of `method` with `result`, and
    /// tells how long the call took.
    func answer(
        _ method: String, with result: String, on harness: CodexServerHarness, _ call: @escaping @Sendable () async throws -> Void
    ) async throws -> Duration {
        let start = ContinuousClock.now
        let caller = Task { try await call() }
        while let line = await harness.nextWritten() {
            guard line["method"] == .string(method), let identifier = line["id"]?.integer else { continue }
            harness.serve(#"{"id":\#(identifier),"result":\#(result)}"#)
            break
        }
        try await caller.value
        return ContinuousClock.now - start
    }

    @Test func theOtherThreadsGetTheirAnswersAtOnce() async throws {
        let harness = try await CodexServerHarness(options: options)
        let server = harness.server
        let stalled = await server.open("stalled", first: [])
        _ = await server.open("other", first: [])
        for index in 0..<30 { harness.serve(delta(index)) }
        let usage = try await answer("account/rateLimits/read", with: #"{"rateLimits":{}}"#, on: harness) { _ = try await server.readUsage() }
        let stop = try await answer("thread/backgroundTerminals/list", with: #"{"data":[]}"#, on: harness) { _ = await server.stop(thread: "other") }
        let start = try await answer("thread/start", with: #"{"thread":{"id":"new"}}"#, on: harness) {
            _ = try await server.startThread(CodexThreadStart(folder: "/work/project"))
        }
        #expect([usage, stop, start].allSatisfy { $0 < .seconds(1) })
        #expect(stalled.state.withLock { $0.events.count } == 5)
    }

    @Test func aFloodToAStalledThreadKeepsItsEventsBounded() async throws {
        let harness = try await CodexServerHarness(options: options)
        let stalled = await harness.server.open("stalled", first: [])
        for index in 0..<10_000 { harness.serve(delta(index)) }
        // The answer comes after the flood, so the reader read all of it.
        _ = try await answer("account/rateLimits/read", with: #"{"rateLimits":{}}"#, on: harness) { _ = try await harness.server.readUsage() }
        #expect(stalled.state.withLock { $0.events.count } == 5)
    }
}
