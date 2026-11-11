import Foundation
import Testing
import AgentConversation

/// One event of each kind, so a test can go through all of them.
let oneEventOfEachKind: [ConversationEventKind] = [
    .agentStarted(AgentStart(conversationIdentifier: "c", model: "m", permissionMode: "default", agentVersion: "2.1.322")),
    .userMessage(UserMessage(identifier: "u", text: "Hi", imageCount: 1, isAccepted: false)),
    .turnStarted(TurnStart(userMessageIdentifier: "u")),
    .agentTextDelta(AgentTextDelta(itemIdentifier: "t", text: "o")),
    .agentText(AgentText(itemIdentifier: "t", text: "ok")),
    .thinking(Thinking(itemIdentifier: "k", estimatedTokens: 50, isComplete: false)),
    .toolCallStarted(ToolCallStart(identifier: "c1", name: "Bash")),
    .toolCallInputDelta(ToolCallInputDelta(identifier: "c1", partialInput: "{\"com")),
    .toolCallInput(ToolCallInput(identifier: "c1", name: "Bash", input: .object(["command": .string("ls")]))),
    .toolCallOutput(ToolCallOutput(identifier: "c1", text: "a\n")),
    .toolCallResult(ToolCallResult(identifier: "c1", output: "a", outputByteCount: 9, isError: false, exitCode: 0)),
    .toolCallRefused(ToolCallRefusal(identifier: "c1", toolName: "Bash", reason: .rule, message: "No")),
    .fileChange(FileChange(identifier: "f", toolCallIdentifier: "c1", path: "a.txt", kind: .modified, diff: "-a\n+b")),
    .taskStarted(TaskStart(identifier: "s", toolCallIdentifier: "c2", description: "Check", agentType: nil, prompt: "Go")),
    .taskMessage(TaskMessage(toolCallIdentifier: "c2", text: "Go")),
    .taskEnded(TaskEnd(identifier: "s", toolCallIdentifier: "c2", status: "completed", summary: "ok")),
    .permissionRequested(PermissionRequest(identifier: "p", toolName: "Bash", input: .null, toolCallIdentifier: "c1")),
    .permissionEnded(PermissionEnd(identifier: "p", outcome: .denied, message: "No")),
    .turnEnded(TurnEnd(outcome: .done, usage: TokenUsage(inputTokens: 1, outputTokens: 2), durationMilliseconds: 3)),
    .usage(UsageReading(windows: [UsageWindow(name: "seven_day", lengthInMinutes: 10080, usedFraction: 0.07,
                                              resetTime: Date(timeIntervalSince1970: 1_794_780_000), status: "allowed")],
                        status: "allowed", otherFields: ["isUsingOverage": .bool(false)])),
    .notice(Notice(level: .warning, text: "Retry")),
    .agentStatus(AgentStatus(kind: "system/status", detail: "requesting")),
    .processEnded(ProcessEnd(exitStatus: 1, wasRequested: false, standardErrorText: "No conversation")),
    .unknown(UnknownLine(reason: .unknownKind, kind: "new_kind", text: "{}", byteCount: 2)),
]

@Suite struct ConversationEventTests {
    @Test func eachKindOfEventSurvivesAnEncodeAndADecode() throws {
        for kind in oneEventOfEachKind {
            let event = ConversationEvent(kind, sourceLine: SourceLine(bytes: Array("{\"type\":\"x\"}".utf8)))
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(ConversationEvent.self, from: data) == event)
        }
    }

    @Test func onlyAnEndThatOpenRunDidNotAskForCanFail() {
        #expect(ProcessEnd(exitStatus: 1, wasRequested: false).isFailure)
        #expect(ProcessEnd(exitStatus: nil, signal: 9, wasRequested: false).isFailure)
        #expect(!ProcessEnd(exitStatus: 0, wasRequested: false).isFailure)
        #expect(!ProcessEnd(exitStatus: nil, signal: 2, wasRequested: true).isFailure)
    }
}
