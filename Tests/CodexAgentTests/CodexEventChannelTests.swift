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

    /// A command that prints 5,000 small pieces at one time fills one place.
    @Test func piecesThatWaitJoinAndCountAsOneEvent() async {
        let channel = CodexEventChannel(limit: 3)
        let text = CodexEventPiecesTests.text, output = CodexEventPiecesTests.output
        for _ in 0..<5_000 { #expect(channel.add(output("c", "x"))) }
        #expect(channel.add(text("m", "a", nil)) && channel.add(text("m", "b", nil)) && channel.add(event(1)))
        #expect(!channel.add(text("m", "c", nil)))
        channel.finish()
        var received: [ConversationEvent] = []
        for await event in channel.stream { received.append(event) }
        #expect(received == [output("c", String(repeating: "x", count: 5_000)), text("m", "ab", nil), event(1)])
    }

    @Test func theBytesThatWaitHaveALimitAndOneLargeEventCanWaitAlone() async {
        let channel = CodexEventChannel(limit: 100, byteLimit: 1_000)
        let text = CodexEventPiecesTests.text
        #expect(channel.add(text("m", "a", 5_000)))
        #expect(!channel.add(text("m", "b", 1)))
        #expect(await channel.next() == text("m", "a", 5_000))
        #expect(channel.add(text("m", "b", 600)) && channel.add(text("m", "c", 400)))
        #expect(!channel.add(text("n", "d", 1)))
        #expect(await channel.next() == text("m", "bc", 600))
        #expect(channel.add(text("n", "d", 1_000)))
    }

    @Test func aCancelledReaderGetsNil() async throws {
        let channel = CodexEventChannel(limit: 10)
        let reader = Task { await channel.next() }
        try await Task.sleep(for: .milliseconds(50))
        reader.cancel()
        #expect(await reader.value == nil)
    }
}
