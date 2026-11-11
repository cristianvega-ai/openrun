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

    @Test func aCommandThatFailsIsAnError() {
        var mapper = CodexEventMapper()
        let item = JSONValue.object(["type": .string("commandExecution"), "id": .string("c"), "status": .string("failed"),
                                     "aggregatedOutput": .string("no such file"), "exitCode": .number(1)])
        #expect(mapper.events(method: "item/completed", parameters: .object(["item": item]))
            == [.toolCallResult(ToolCallResult(identifier: "c", output: "no such file", isError: true, exitCode: 1))])
    }
}
