import AgentConversation
import MarkdownText
import Testing

@testable import ChatView

@MainActor struct TranscriptSearchTests {
    @Test func everyMatchInEveryRowIsFoundInOrder() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        context.transcript = SampleConversation.transcript
        var builder = TranscriptRowBuilder()
        let rows = builder.rows(for: context.transcript, changedItems: nil, showsEarlierItems: false)
        context.documents = builder.documents
        let matches = TranscriptSearch.matches(of: "transcript", in: rows, context: context)
        #expect(matches.first?.rowKey == "user:1")
        #expect(Set(matches.map(\.rowKey)).isSuperset(of: ["text:a1#0", "group:tool:t1", "file:e1"]))
        #expect(matches.count > 8)
        #expect(TranscriptSearch.matches(of: "", in: rows, context: context).isEmpty)
        #expect(TranscriptSearch.matches(of: "ÉARLIER ITEMS", in: rows, context: context).first?.rowKey == "user:1")
    }
}
