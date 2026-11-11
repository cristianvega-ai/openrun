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

    @Test func aMessageThatComesInATurnWaitsAndOneProcessTakesBothTurns() async throws {
        let settings = FakeAgentSettings.make(turns: ["plain-turn", "edit-turn"], environment: ["FAKE_AGENT_PAUSE": "2"])
        let runner = ThreadRunner(record: FakeAgentSettings.record()) { settings }
        try await runner.send(text: "Reply with the single word ok.")
        let process = await runner.program?.processIdentifier
        try await runner.send(text: "Change the file.")
        #expect(await runner.waitingMessages.count == 1)
        #expect(await eventually {
            let (file, isBusy) = await (runner.transcript.item(withIdentifier: "file:toolu_01Fixture00000000000005"), runner.isBusy)
            return file != nil && !isBusy
        })
        let turnEnds = await runner.keptEvents.filter { if case .turnEnded = $0.kind { true } else { false } }
        #expect(turnEnds.count == 2 && process != nil)
        #expect(await runner.program?.processIdentifier == process)
        await runner.close()
    }

    @Test func theSeventeenthMessageThatWaitsIsRefused() async throws {
        let runner = ThreadRunner(record: FakeAgentSettings.record()) { FakeAgentSettings.make(mode: "neverEnds") }
        for number in 0...ThreadRunner.waitingMessageLimit { try await runner.send(text: "Message \(number)") }
        await #expect(throws: ThreadRunnerError.tooManyWaitingMessages(limit: 16)) { try await runner.send(text: "One more") }
        await runner.close()
        await #expect(throws: ThreadRunnerError.threadIsClosed) { try await runner.send(text: "After the close") }
    }
}
