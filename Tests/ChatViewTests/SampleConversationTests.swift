import AgentConversation
import Testing

@testable import ChatView

struct SampleConversationTests {
    @Test func theFirstTurnHasEveryKindOfRowOfAnAnswer() {
        var builder = TranscriptRowBuilder()
        let rows = builder.rows(for: SampleConversation.transcript, changedItems: nil, showsEarlierItems: false)
        let kinds = Set(rows.map { "\($0.kind)".prefix(while: { $0 != "(" }) })
        #expect(kinds.isSuperset(of: ["userMessage", "agentText", "agentCode", "toolCalls", "fileChange", "permissionRequest"]))
    }
}
