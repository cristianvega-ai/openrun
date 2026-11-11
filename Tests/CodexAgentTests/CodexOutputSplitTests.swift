import AgentConversation
import Testing
@testable import CodexAgent

/// The output of the app-server comes from a pipe in pieces of any size,
/// so a split at any place must give the same events as the whole output.
@Suite struct CodexOutputSplitTests {
    static let recordings = ["plain-turn", "command-accepted", "command-declined", "file-change"]

    /// A plain turn and a text delta with characters of two, three and
    /// four bytes that a split can cut.
    func sample() throws -> [UInt8] {
        let text = #"{"method":"item/agentMessage/delta","params":{"itemId":"m","delta":"é – 😀"}}"#
        return try CodexFixture(name: "plain-turn").serverBytes + Array((text + "\n").utf8)
    }

    @Test func aSplitAtEachByteGivesTheSameEvents() throws {
        let bytes = try sample()
        let whole = CodexFixture.events(of: [bytes[...]])
        #expect(whole.last == .agentTextDelta(AgentTextDelta(itemIdentifier: "m", text: "é – 😀")))
        for position in 0...bytes.count where CodexFixture.events(of: [bytes[..<position], bytes[position...]]) != whole {
            Issue.record("The split at byte \(position) gave other events")
            return
        }
    }

    @Test func randomPiecesOfRecordedTurnsGiveTheSameEvents() throws {
        var generator = SeededGenerator(seed: 0xC0DE)
        for name in Self.recordings {
            let bytes = try CodexFixture(name: name).serverBytes
            let whole = CodexFixture.events(of: [bytes[...]])
            for _ in 0..<10 {
                var pieces: [ArraySlice<UInt8>] = []
                var start = 0
                while start < bytes.count {
                    let end = min(bytes.count, start + Int.random(in: 0...700, using: &generator))
                    pieces.append(bytes[start..<end])
                    start = end
                }
                #expect(CodexFixture.events(of: pieces) == whole, "\(name)")
            }
        }
    }
}
