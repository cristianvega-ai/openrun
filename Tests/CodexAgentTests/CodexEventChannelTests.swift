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

    @Test func anEventAboveTheLimitIsRefusedAndTheLastEventIsNot() async {
        let channel = CodexEventChannel(limit: 2)
        #expect(channel.add(event(0)) && channel.add(event(1)))
        #expect(!channel.add(event(2)))
        #expect(await channel.next() == event(0))
        #expect(channel.add(event(2)))
        channel.finish(with: event(3))
        var received: [ConversationEvent] = []
        for await event in channel.stream { received.append(event) }
        #expect(received == [1, 2, 3].map(event))
    }

    @Test func theFinishGivesTheLastEventToAWaitingReader() async throws {
        let channel = CodexEventChannel(limit: 0)
        let reader = Task { await channel.next() }
        try await Task.sleep(for: .milliseconds(50))
        channel.finish(with: event(1))
        #expect(await reader.value == event(1))
        #expect(await channel.next() == nil)
    }

    @Test func aCancelledReaderGetsNil() async throws {
        let channel = CodexEventChannel(limit: 10)
        let reader = Task { await channel.next() }
        try await Task.sleep(for: .milliseconds(50))
        reader.cancel()
        #expect(await reader.value == nil)
    }
}
