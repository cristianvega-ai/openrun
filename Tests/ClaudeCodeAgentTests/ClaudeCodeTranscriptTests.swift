import AgentConversation
import Testing

/// The transcript of each recorded turn, as a chat shows it.
@Suite struct ClaudeCodeTranscriptTests {
    func identifiers(_ name: String) throws -> [String] {
        try Fixture(name: name).transcript.items.map(\.identifier)
    }

    func toolCall(_ transcript: Transcript, _ identifier: String) -> ToolCallItem? {
        if case .toolCall(let call) = transcript.item(withIdentifier: "tool:" + identifier)?.content { call } else { nil }
    }

    @Test func textAfterHiddenThinkingKeepsOneItem() throws {
        let transcript = try Fixture(name: "image-turn").transcript
        #expect(transcript.items.map(\.identifier) == ["user:00000000-0000-4000-8000-000000000116", "text:msg_01Fixture00000000000008:1", "turn:12"])
        #expect(transcript.items.first?.content == .userMessage(UserMessage(
            identifier: "00000000-0000-4000-8000-000000000116", text: "What color is this image? Reply with one word.\n[image]",
            imageCount: 1, isAccepted: true)))
    }

    @Test func anAllowedCommandSucceedsWithItsOutput() throws {
        let transcript = try Fixture(name: "command-turn").transcript
        #expect(try identifiers("command-turn") == [
            "user:00000000-0000-4000-8000-000000000018", "tool:toolu_01Fixture00000000000001", "text:msg_01Fixture00000000000003:0", "turn:36",
        ])
        let call = toolCall(transcript, "toolu_01Fixture00000000000001")
        #expect(call?.name == "Bash")
        #expect(call?.state == .succeeded)
        #expect(call?.output == "/work/project\ncreated\nhi")
        #expect(transcript.thinking == nil)
    }

    @Test func aDeniedCommandIsRefusedByTheUserWithTheMessage() throws {
        let transcript = try Fixture(name: "denied-turn").transcript
        let call = toolCall(transcript, "toolu_01Fixture00000000000002")
        #expect(call?.state == .refused)
        #expect(call?.refusal == ToolCallRefusal(
            identifier: "toolu_01Fixture00000000000002", toolName: "Bash", reason: .user,
            message: "The user denied this command. Use the command `echo denied` instead."))
        #expect(transcript.items.count == 4)
    }

    @Test func anEditGivesTheChangeOfTheFile() throws {
        let transcript = try Fixture(name: "edit-turn").transcript
        #expect(transcript.item(withIdentifier: "file:toolu_01Fixture00000000000005")?.content == .fileChange(FileChange(
            identifier: "toolu_01Fixture00000000000005", toolCallIdentifier: "toolu_01Fixture00000000000005",
            path: "/work/project/notes.txt", kind: .modified, diff: "@@ -1,1 +1,1 @@\n-hi\n+hello")))
        #expect(toolCall(transcript, "toolu_01Fixture00000000000004")?.output == "1\thi\n2\t")
    }

    @Test func aSubAgentGivesATaskWithItsMessageAndEnd() throws {
        let transcript = try Fixture(name: "sub-agent-turn").transcript
        guard case .task(let task) = transcript.item(withIdentifier: "task:a0000000000000001")?.content else {
            Issue.record("No task")
            return
        }
        #expect(task.start?.agentType == "general-purpose")
        #expect(task.messages == ["Reply with the single word ok."])
        #expect(task.end == TaskEnd(
            identifier: "a0000000000000001", toolCallIdentifier: "toolu_01Fixture00000000000003", status: "completed", summary: "ok"))
    }

    @Test func aStoppedTurnAndAFailedLoginEndAsTheySay() throws {
        let stopped = try Fixture(name: "stopped-turn").transcript
        #expect(stopped.state == .idle)
        #expect(toolCall(stopped, "toolu_01Fixture00000000000006")?.state == .failed)
        #expect(stopped.items.dropFirst().first?.content == .notice(Notice(level: .information, text: "[Request interrupted by user for tool use]")))
        let failed = try Fixture(name: "authentication-failure").transcript
        #expect(failed.state == .failed)
        guard case .turnEnd(let end) = failed.items.last?.content else { return }
        #expect(end.errorText?.hasPrefix("Failed to authenticate") == true)
    }
}
