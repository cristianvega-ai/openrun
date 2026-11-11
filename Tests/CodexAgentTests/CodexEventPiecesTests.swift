import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexEventPiecesTests {
    static func text(_ item: String, _ text: String, bytes: Int? = nil) -> ConversationEvent {
        ConversationEvent(.agentTextDelta(AgentTextDelta(itemIdentifier: item, text: text)), sourceLine: bytes.map { SourceLine(text: "", byteCount: $0) })
    }

    static func output(_ call: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.toolCallOutput(ToolCallOutput(identifier: call, text: text)))
    }

    static func thinking(_ item: String, tokens: Int? = nil, isComplete: Bool = false) -> ConversationEvent {
        ConversationEvent(.thinking(Thinking(itemIdentifier: item, estimatedTokens: tokens, isComplete: isComplete)))
    }

    @Test func piecesOfOneItemJoinInOrderAndKeepTheFirstLine() {
        let joined = CodexEventPieces.joined(Self.text("m", "a", bytes: 10), Self.text("m", "b", bytes: 20))
        #expect(joined == Self.text("m", "ab", bytes: 10))
        #expect(CodexEventPieces.joined(Self.output("c", "x"), Self.output("c", "y")) == Self.output("c", "xy"))
        let input = { ConversationEvent(.toolCallInputDelta(ToolCallInputDelta(identifier: "c", partialInput: $0))) }
        #expect(CodexEventPieces.joined(input("{\"a\":"), input("1}")) == input("{\"a\":1}"))
    }

    @Test func theNewerStateOfTheThinkingReplacesTheOlderOne() {
        let done = Self.thinking("r", tokens: 9, isComplete: true)
        #expect(CodexEventPieces.joined(Self.thinking("r", tokens: 1), Self.thinking("r", tokens: 5)) == Self.thinking("r", tokens: 5))
        #expect(CodexEventPieces.joined(Self.thinking("r"), done) == done)
        #expect(CodexEventPieces.joined(done, Self.thinking("r")) == nil)
    }

    @Test func piecesOfTwoItemsAndOtherEventsStayApart() {
        let notice = ConversationEvent(.notice(Notice(level: .information, text: "n")))
        #expect(CodexEventPieces.joined(Self.text("m", "a"), Self.text("n", "b")) == nil)
        #expect(CodexEventPieces.joined(Self.text("m", "a"), Self.output("m", "b")) == nil)
        #expect(CodexEventPieces.joined(Self.thinking("r"), Self.thinking("s")) == nil)
        #expect(CodexEventPieces.joined(notice, notice) == nil)
    }

    @Test func anEventTakesTheRoomOfItsLine() {
        #expect(CodexEventPieces.byteCount(of: Self.text("m", "a", bytes: 300)) == 300)
        #expect(CodexEventPieces.byteCount(of: Self.text("m", "a")) == 0)
    }
}
