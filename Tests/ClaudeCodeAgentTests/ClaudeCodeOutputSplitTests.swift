import AgentConversation
import ClaudeCodeAgent
import Testing

/// The output comes from a pipe in pieces of any size, so a split at any
/// place must give the same events as the whole output.
@Suite struct ClaudeCodeOutputSplitTests {
    func decode(_ pieces: [ArraySlice<UInt8>]) -> [ConversationEvent] {
        var decoder = ClaudeCodeOutputDecoder()
        return pieces.flatMap { decoder.decode($0) } + decoder.finish()
    }

    /// Lines of a plain turn, and a text piece with characters of two,
    /// three and four bytes that a split can cut.
    func sample() throws -> [UInt8] {
        let lines = try String(decoding: Fixture(name: "plain-turn").bytes, as: UTF8.self).split(separator: "\n")
        let text = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"#
            + #""delta":{"type":"text_delta","text":"é – 😀"}},"api_message_id":"m"}"#
        return Array(([lines[0], lines[1], lines[3], lines[5], lines[7], lines[8]].joined(separator: "\n") + "\n" + text + "\n").utf8)
    }

    @Test func aSplitAtEachByteGivesTheSameEvents() throws {
        let bytes = try sample()
        let whole = decode([bytes[...]])
        #expect(whole.count == 7)
        #expect(whole.last?.kind == .agentTextDelta(AgentTextDelta(itemIdentifier: "m:0", text: "é – 😀")))
        for position in 0...bytes.count {
            let events = decode([bytes[..<position], bytes[position...]])
            if events != whole {
                Issue.record("The split at byte \(position) gave other events")
                return
            }
        }
    }

    @Test func randomPiecesOfRecordedTurnsGiveTheSameEvents() throws {
        var generator = SeededGenerator(seed: 0x5EED)
        for name in Fixture.turns {
            let bytes = try Fixture(name: name).bytes
            let whole = decode([bytes[...]])
            for _ in 0..<10 {
                var pieces: [ArraySlice<UInt8>] = []
                var start = 0
                while start < bytes.count {
                    let end = min(bytes.count, start + Int.random(in: 0...700, using: &generator))
                    pieces.append(bytes[start..<end])
                    start = end
                }
                #expect(decode(pieces) == whole, "\(name)")
            }
        }
    }
}
