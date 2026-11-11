import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerStopTests {
    @Test func aCodexWithoutTheExperimentalMethodsStillStopsAndSaysSo() async throws {
        let harness = try await CodexServerHarness()
        let channel = await harness.server.open("a", first: [])
        let stop = Task { await harness.server.stop(thread: "a") }
        let list = await harness.nextWritten()
        #expect(list?["method"] == .string("thread/backgroundTerminals/list"))
        harness.serve(#"{"id":\#(list?["id"]?.integer ?? 0),"error":{"code":-32601,"message":"unknown method"}}"#)
        #expect(await stop.value == CodexStop(commandsMayStillRun: true))
        #expect(await channel.next()?.kind == .notice(Notice(
            level: .warning, text: "OpenRun could not end the commands of the thread, so a command may still run.")))
    }
}
