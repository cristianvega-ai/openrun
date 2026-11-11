import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexEventChannelTests {
    func event(_ number: Int) -> ConversationEvent {
        ConversationEvent(.notice(Notice(level: .information, text: "\(number)")))
    }

    @Test func theCallerGetsTheEventsInOrderAndThenTheEnd() async {
        let channel = CodexEventChannel(limit: 100)
        for number in 0..<5 { channel.add(event(number)) }
        channel.finish()
        channel.add(event(9))
        var received: [ConversationEvent] = []
        for await event in channel.stream { received.append(event) }
        #expect(received == (0..<5).map(event))
    }
}
