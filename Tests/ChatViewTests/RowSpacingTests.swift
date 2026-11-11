import Testing

@testable import ChatView

struct RowSpacingTests {
    let user = TranscriptRow(key: "user:1", kind: .userMessage(item: "user:1"))
    let text = TranscriptRow(key: "text:a#0", kind: .agentText(item: "text:a", blocks: 0..<1))
    let tools = TranscriptRow(key: "group:tool:1", kind: .toolCalls(items: ["tool:1"]))
    let notice = TranscriptRow(key: "notice:1", kind: .notice(item: "notice:1"))

    @Test func aNewMessageOfTheUserHasTheMostSpace() {
        #expect(RowSpacing.above(user, after: nil) == RowSpacing.top)
        #expect(RowSpacing.above(user, after: text) > RowSpacing.above(text, after: user))
        #expect(RowSpacing.above(text, after: user) > RowSpacing.above(tools, after: text))
        #expect(RowSpacing.above(notice, after: tools) < RowSpacing.above(tools, after: text))
    }
}
