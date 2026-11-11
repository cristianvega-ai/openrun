import AgentConversation
import AgentThreads
import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

@Suite struct ThreadRunnerTests {
    @Test func aMessageRunsATurnToItsEndAndTheThreadKeepsTheConversation() async throws {
        let runner = ThreadRunner(record: FakeAgentSettings.record()) { FakeAgentSettings.make() }
        let identifier = try await runner.send(text: "Reply with the single word ok.")
        #expect(await eventually { await runner.state == .finishedTurn })
        #expect(await runner.agentTexts == ["ok"])
        let message = await runner.transcript.item(withIdentifier: "user:" + identifier.uuidString.lowercased())
        #expect(message?.content == .userMessage(UserMessage(identifier: identifier.uuidString.lowercased(), text: "Reply with the single word ok.", isAccepted: true)))
        let record = await runner.record
        #expect(record.hasConversation && record.title == "Reply with the single word ok.")
        let (isRunning, isBusy) = await (runner.isProcessRunning, runner.isBusy)
        #expect(isRunning && !isBusy)
        await runner.close()
        #expect(await !runner.isProcessRunning)
    }
}
