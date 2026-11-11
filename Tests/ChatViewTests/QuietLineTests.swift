import AgentConversation
import Testing

@testable import ChatView

struct QuietLineTests {
    @Test func aFailedTurnSaysWhyAndAStoppedTurnIsShort() {
        let failed = QuietLine(.turnEnd(TurnEnd(outcome: .failed, errorText: "API Error: overloaded")))
        #expect(failed?.title == "The turn failed: API Error: overloaded")
        #expect(failed?.details == [])
        #expect(QuietLine(.turnEnd(TurnEnd(outcome: .stopped)))?.title == "Stopped")
    }

    @Test func aTaskOpensToItsPromptAndMessages() {
        var task = TaskItem(start: TaskStart(identifier: "t", toolCallIdentifier: "c", description: "Find the tests", agentType: nil, prompt: "Look"))
        task.messages = ["Found two."]
        let line = QuietLine(.task(task))
        #expect(line?.title == "Find the tests")
        #expect(line?.status == "Running")
        #expect(line?.details == ["Look", "Found two."])
    }

    @Test func aNoticeOfManyLinesOpensAndAnUnknownLineShowsItsText() {
        #expect(QuietLine(.notice(Notice(level: .warning, text: "Retry\nin 4 seconds")))?.details == ["Retry\nin 4 seconds"])
        #expect(QuietLine(.notice(Notice(level: .information, text: "Compacted")))?.details == [])
        let unknown = QuietLine(.unknown(UnknownLine(reason: .unknownKind, kind: "rate_limit", text: "{\"type\":1}", byteCount: 11)))
        #expect(unknown?.status == "Kind rate_limit")
        #expect(unknown?.details == ["{\"type\":1}"])
    }
}
