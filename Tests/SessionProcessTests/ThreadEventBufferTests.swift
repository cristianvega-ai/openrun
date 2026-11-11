import AgentConversation
import Foundation
import Testing
@testable import SessionProcess

@Suite struct ThreadEventBufferTests {
    static func text(_ text: String) -> ConversationEvent {
        ConversationEvent(.agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: text)))
    }

    static let turnEnd = ConversationEvent(.turnEnded(TurnEnd(outcome: .done)))

    private func texts(_ buffer: ThreadEventBuffer) throws -> [String] {
        try buffer.entries.map { entry in
            let event = try JSONDecoder().decode(ConversationEvent.self, from: entry.data)
            if case .agentTextDelta(let delta) = event.kind { return delta.text }
            return "end"
        }
    }

    @Test func theBufferKeepsTheEventsAsTheJSONOfTheClients() throws {
        var buffer = ThreadEventBuffer()
        let data = buffer.append(Self.text("hello"))
        #expect(try JSONDecoder().decode(ConversationEvent.self, from: data) == Self.text("hello"))
        _ = buffer.append(Self.turnEnd)
        #expect(try texts(buffer) == ["hello", "end"] && !buffer.hasEarlierEvents)
        #expect(buffer.byteCount == buffer.entries.reduce(0) { $0 + $1.data.count })
    }

    @Test func wholeTurnsGoFirstSoTheRestStartsAtATurn() throws {
        var probe = ThreadEventBuffer()
        let size = probe.append(Self.text("one")).count
        var buffer = ThreadEventBuffer(byteLimit: 6 * size)
        for text in ["one", "two"] { _ = buffer.append(Self.text(text)) }
        _ = buffer.append(Self.turnEnd)
        for text in ["six", "ten"] { _ = buffer.append(Self.text(text)) }
        #expect(try texts(buffer) == ["one", "two", "end", "six", "ten"])
        for text in ["red", "tan", "sky"] { _ = buffer.append(Self.text(text)) }
        // The first turn went as a whole, not only its first event.
        #expect(try texts(buffer) == ["six", "ten", "red", "tan", "sky"] && buffer.hasEarlierEvents)
        #expect(buffer.byteCount <= 6 * size)
    }

    @Test func aTurnLargerThanTheLimitLosesItsOldestEventsAndTheNewestStays() throws {
        var probe = ThreadEventBuffer()
        let size = probe.append(Self.text("one")).count
        var buffer = ThreadEventBuffer(byteLimit: 2 * size)
        for text in ["one", "two", "six"] { _ = buffer.append(Self.text(text)) }
        #expect(try texts(buffer) == ["two", "six"])
        _ = buffer.append(Self.text(String(repeating: "x", count: 10 * size)))
        #expect(buffer.entries.count == 1 && buffer.byteCount > buffer.byteLimit)
    }
}
