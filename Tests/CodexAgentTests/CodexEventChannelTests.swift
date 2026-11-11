import AgentConversation
import Synchronization
import Testing
@testable import CodexAgent

@Suite struct CodexEventChannelTests {
    func event(_ number: Int) -> ConversationEvent {
        ConversationEvent(.notice(Notice(level: .information, text: "\(number)")))
    }

    @Test func theCallerGetsTheEventsInOrderAndThenTheEnd() async {
        let channel = CodexEventChannel(limit: 100)
        for number in 0..<5 { await channel.send(event(number)) }
        channel.finish()
        channel.add(event(9))
        var received: [ConversationEvent] = []
        for await event in channel.stream { received.append(event) }
        #expect(received == (0..<5).map(event))
    }

    @Test func theSenderWaitsWhileTooManyEventsWait() async throws {
        let channel = CodexEventChannel(limit: 2)
        let sent = Atomic<Int>(0)
        let sender = Task {
            for number in 0..<10 {
                await channel.send(event(number))
                sent.add(1, ordering: .sequentiallyConsistent)
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(sent.load(ordering: .sequentiallyConsistent) <= 3)
        var received: [ConversationEvent] = []
        for _ in 0..<10 { if let event = await channel.next() { received.append(event) } }
        await sender.value
        #expect(received == (0..<10).map(event))
    }

    @Test func theFinishReleasesTheSenderAndTheReader() async throws {
        let channel = CodexEventChannel(limit: 0)
        let reader = Task { await channel.next() }
        try await Task.sleep(for: .milliseconds(50))
        let sender = Task { await channel.send(event(1)); await channel.send(event(2)) }
        try await Task.sleep(for: .milliseconds(50))
        channel.finish()
        await sender.value
        #expect(await reader.value == event(1))
        #expect(await channel.next() == event(2))
        #expect(await channel.next() == nil)
    }
}
