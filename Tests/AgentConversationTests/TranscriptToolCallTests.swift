import Testing
import AgentConversation

@Suite struct TranscriptToolCallTests {
    func toolCall(in transcript: Transcript, _ identifier: String) -> ToolCallItem? {
        guard case .toolCall(let call) = transcript.item(withIdentifier: "tool:" + identifier)?.content else { return nil }
        return call
    }

    @Test func aCallFollowsItsInputItsOutputAndItsResult() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.toolCallStarted(ToolCallStart(identifier: "c", name: "Bash"))))
        transcript.apply(ConversationEvent(.toolCallInputDelta(ToolCallInputDelta(identifier: "c", partialInput: "{\"command\":"))))
        #expect(toolCall(in: transcript, "c")?.inputText == "{\"command\":")
        #expect(toolCall(in: transcript, "c")?.state == .preparing)
        transcript.apply(ConversationEvent(.toolCallInput(ToolCallInput(identifier: "c", name: "Bash", input: .object(["command": .string("ls")])))))
        #expect(toolCall(in: transcript, "c")?.state == .running)
        transcript.apply(ConversationEvent(.toolCallOutput(ToolCallOutput(identifier: "c", text: "a.txt\n"))))
        transcript.apply(ConversationEvent(.toolCallResult(ToolCallResult(identifier: "c", output: "a.txt", isError: false, exitCode: 0))))
        let call = toolCall(in: transcript, "c")
        #expect(call?.state == .succeeded)
        #expect(call?.input == .object(["command": .string("ls")]))
        #expect(call?.output == "a.txt")
        #expect(call?.exitCode == 0)
        #expect(transcript.items.count == 1)
    }

    @Test func aRefusedCallStaysRefusedAfterItsResult() {
        var transcript = Transcript()
        let refusal = ToolCallRefusal(identifier: "c", toolName: "Bash", reason: .user, message: "No")
        transcript.apply(ConversationEvent(.toolCallRefused(refusal)))
        transcript.apply(ConversationEvent(.toolCallResult(ToolCallResult(identifier: "c", output: "No", isError: true))))
        #expect(toolCall(in: transcript, "c")?.state == .refused)
        #expect(toolCall(in: transcript, "c")?.refusal == refusal)
        transcript.apply(ConversationEvent(.toolCallRefused(ToolCallRefusal(identifier: nil, toolName: "Write", reason: .mode, message: "Mode"))))
        #expect(transcript.items.last?.content == .notice(Notice(level: .warning, text: "Write was refused: Mode")))
    }

    @Test func aCallThatRunsAtTheEndOfTheTurnIsInterrupted() {
        var transcript = Transcript()
        transcript.apply(ConversationEvent(.toolCallInput(ToolCallInput(identifier: "c", name: "Bash", input: .null))))
        transcript.apply(ConversationEvent(.turnEnded(TurnEnd(outcome: .stopped))))
        #expect(toolCall(in: transcript, "c")?.state == .interrupted)
    }

    @Test func largeInputAndOutputKeepOnlyTheirStart() {
        var transcript = Transcript(limits: TranscriptLimits(detailByteLimit: 16))
        let content = String(repeating: "x", count: 1000)
        transcript.apply(ConversationEvent(.toolCallInput(ToolCallInput(identifier: "c", name: "Write", input: .object(["content": .string(content)])))))
        for _ in 0..<10 { transcript.apply(ConversationEvent(.toolCallOutput(ToolCallOutput(identifier: "c", text: content)))) }
        let call = toolCall(in: transcript, "c")
        #expect(call?.input == .string("{\"content\":\"xxxx"))
        #expect(call?.output.utf8.count == 16)
        #expect(call?.outputByteCount == 10_000)
    }

    @Test func aFileChangeIsAnItemWithItsDiff() {
        var transcript = Transcript()
        let fileChange = FileChange(identifier: "f", toolCallIdentifier: "c", path: "notes.txt", kind: .modified, diff: "-hi\n+hello")
        transcript.apply(ConversationEvent(.fileChange(fileChange)))
        #expect(transcript.items == [TranscriptItem(identifier: "file:f", content: .fileChange(fileChange))])
    }
}
