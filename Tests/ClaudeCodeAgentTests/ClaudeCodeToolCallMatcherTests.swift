import AgentConversation
import ClaudeCodeAgent
import Foundation
import Testing

@Suite struct ClaudeCodeToolCallMatcherTests {
    let touch = JSONValue.object(["command": .string("touch a")])

    func input(_ identifier: String, _ input: JSONValue, name: String = "Bash") -> ConversationEvent {
        ConversationEvent(.toolCallInput(ToolCallInput(identifier: identifier, name: name, input: input)))
    }

    @Test func theRecordedRequestMatchesItsCallInTheOutput() throws {
        var matcher = ClaudeCodeToolCallMatcher()
        let request = try ClaudeCodePermissionHookRequest(
            decoding: Data(contentsOf: Fixture.folder.appending(path: "permission-request.json")))
        matcher.observe(input("t1", .object(["command": .string("touch approved.txt")])))
        matcher.observe(input("t2", .object([
            "command": .string("touch approved.txt"), "description": .string("Create empty approved.txt file with touch"),
        ])))
        #expect(matcher.claim(toolName: request.toolName, input: request.toolInput) == "t2")
        #expect(matcher.claim(toolName: request.toolName, input: request.toolInput) == nil)
    }

    @Test func twoEqualCallsGoToTheRequestsOldestFirst() {
        var matcher = ClaudeCodeToolCallMatcher()
        matcher.observe(input("t1", touch))
        matcher.observe(input("t2", touch))
        matcher.observe(input("t1", touch))
        #expect(matcher.claim(toolName: "Read", input: touch) == nil)
        #expect(matcher.claim(toolName: "Bash", input: touch) == "t1")
        #expect(matcher.claim(toolName: "Bash", input: touch) == "t2")
        #expect(matcher.claim(toolName: "Bash", input: touch) == nil)
    }

    @Test func aCallWithAResultOrARefusalOrAfterTheTurnNoLongerMatches() {
        var matcher = ClaudeCodeToolCallMatcher()
        matcher.observe(input("t1", touch))
        matcher.observe(ConversationEvent(.toolCallResult(ToolCallResult(identifier: "t1", output: "", isError: false))))
        matcher.observe(input("t2", touch))
        matcher.observe(ConversationEvent(.toolCallRefused(ToolCallRefusal(identifier: "t2", toolName: "Bash", reason: .rule, message: ""))))
        matcher.observe(input("t3", touch))
        matcher.observe(ConversationEvent(.turnEnded(TurnEnd(outcome: .stopped))))
        #expect(matcher.claim(toolName: "Bash", input: touch) == nil)
    }

    @Test func onlyTheNewestCallsWait() {
        var matcher = ClaudeCodeToolCallMatcher()
        for index in 0...ClaudeCodeToolCallMatcher.callLimit {
            matcher.observe(input("t\(index)", .object(["index": .number(Double(index))])))
        }
        #expect(matcher.claim(toolName: "Bash", input: .object(["index": .number(0)])) == nil)
        #expect(matcher.claim(toolName: "Bash", input: .object(["index": .number(1)])) == "t1")
    }
}
