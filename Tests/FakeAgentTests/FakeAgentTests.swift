import AgentConversation
import AgentProgram
import ClaudeCodeAgent
import Foundation
import Testing

@Suite struct FakeAgentTests {
    @Test func twoTurnsGoThroughTheProgramAndTheDecoderIntoATranscript() async throws {
        let conversation = UUID()
        var run = try FakeAgentRun(turns: ["plain-turn", "edit-turn"], conversation: .new(conversation), environment: ["FAKE_AGENT_PAUSE": "1"])
        let first = try await run.send("Reply with the single word ok.")
        #expect(await run.readTurn()?.outcome == .done)
        #expect(run.transcript.item(withIdentifier: "user:" + first)?.content == .userMessage(UserMessage(
            identifier: first, text: "Reply with the single word ok.", isAccepted: true)))
        #expect(run.transcript.items.contains { if case .agentMessage(let message) = $0.content { message.text == "ok" } else { false } })
        #expect(run.transcript.agentStart?.conversationIdentifier == conversation.uuidString.lowercased())
        _ = try await run.send("Change the file.")
        #expect(await run.readTurn()?.outcome == .done)
        #expect(run.transcript.item(withIdentifier: "file:toolu_01Fixture00000000000005") != nil)
        #expect(run.transcript.state == .finishedTurn)
        // Claude Code ends when its input ends.
        run.program.closeInput()
        #expect(await run.readTurn() == nil)
        #expect(await run.program.waitForExit() == .exited(status: 0))
        #expect(run.events.allSatisfy { if case .unknown = $0.kind { false } else { true } })
    }

    @Test func aCommandLineThatClaudeCodeWouldRefuseEndsTheFakeAgent() async throws {
        let program = try AgentProgram(launching: AgentProgramLaunch(
            executablePath: FakeAgentRun.executable, arguments: ["-p", "--verbose"], folder: "/", environment: [:]))
        #expect(await program.waitForExit() == .exited(status: 64))
        #expect(program.standardErrorText.contains("arguments"))
    }

    @Test func aConversationThatDoesNotExistFailsAtTheStart() async throws {
        let conversation = UUID()
        var run = try FakeAgentRun(turns: ["plain-turn"], mode: "unknownConversation", conversation: .resume(conversation))
        #expect(await run.readTurn()?.outcome == .failed)
        #expect(await run.program.waitForExit() == .exited(status: 1))
        #expect(run.program.standardErrorText == "No conversation found with session ID: \(conversation.uuidString.lowercased())\n")
    }
}
