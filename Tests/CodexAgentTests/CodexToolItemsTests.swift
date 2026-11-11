import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexToolItemsTests {
    let command = "exec-00000000-0000-7000-8000-000000000003"

    @Test func anAcceptedCommandGivesItsInputAndResult() throws {
        let events = try CodexFixture(name: "command-accepted").events
        let input = JSONValue.object(["command": .string("/bin/zsh -lc 'touch x1.txt'"), "cwd": .string("/work/project")])
        #expect(events.contains(.toolCallStarted(ToolCallStart(identifier: command, name: "commandExecution"))))
        #expect(events.contains(.toolCallInput(ToolCallInput(identifier: command, name: "commandExecution", input: input))))
        #expect(events.contains(.toolCallResult(ToolCallResult(identifier: command, output: "", isError: false, exitCode: 0))))
        #expect(events.contains(.agentText(AgentText(itemIdentifier: "msg_01Fixture00000001", text: "Ran `touch x1.txt` successfully."))))
        #expect(!events.contains { if case .unknown = $0 { true } else { false } })
    }

    @Test func aDeclinedCommandIsARefusalOfTheUser() throws {
        let declined = "exec-00000000-0000-7000-8000-000000000007"
        let events = try CodexFixture(name: "command-declined").events
        #expect(events.contains(.toolCallRefused(ToolCallRefusal(
            identifier: declined, toolName: "commandExecution", reason: .user, message: "The user declined it in OpenRun."))))
        #expect(!events.contains { if case .toolCallResult = $0 { true } else { false } })
    }

    @Test func aCommandThatOpenRunDeclinedSaysWhy() {
        var mapper = CodexEventMapper()
        mapper.noteDecline(of: "c", reason: .unanswered)
        let item = JSONValue.object(["type": .string("commandExecution"), "id": .string("c"), "status": .string("declined")])
        #expect(mapper.events(method: "item/completed", parameters: .object(["item": item])) == [.toolCallRefused(ToolCallRefusal(
            identifier: "c", toolName: "commandExecution", reason: .unanswered,
            message: "No one answered the request in time, so OpenRun declined it."))])
        #expect(mapper.declineReasons.isEmpty)
    }

    @Test func aNewFileGivesItsPathAndContentAsADiff() throws {
        let change = "exec-00000000-0000-7000-8000-000000000010"
        let events = try CodexFixture(name: "file-change").events
        let file = FileChange(identifier: change + ":0", toolCallIdentifier: change, path: "/work/project/notes.txt", kind: .added,
                              diff: "@@ -0,0 +1,1 @@\n+hi")
        #expect(events.contains(.fileChange(file)))
        let input = JSONValue.object(["changes": .array([.object(["path": .string("/work/project/notes.txt"), "kind": .string("added")])])])
        #expect(events.contains(.toolCallInput(ToolCallInput(identifier: change, name: "fileChange", input: input))))
        #expect(events.contains(.toolCallResult(ToolCallResult(identifier: change, output: "", isError: false))))
        let transcript = Transcript(events: events.map { ConversationEvent($0) })
        #expect(transcript.items.contains { $0.content == .fileChange(file) })
    }

    @Test func aCommandThatFailsIsAnError() {
        var mapper = CodexEventMapper()
        let item = JSONValue.object(["type": .string("commandExecution"), "id": .string("c"), "status": .string("failed"),
                                     "aggregatedOutput": .string("no such file"), "exitCode": .number(1)])
        #expect(mapper.events(method: "item/completed", parameters: .object(["item": item]))
            == [.toolCallResult(ToolCallResult(identifier: "c", output: "no such file", isError: true, exitCode: 1))])
    }
}
