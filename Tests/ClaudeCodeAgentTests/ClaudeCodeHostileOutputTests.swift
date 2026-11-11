import AgentConversation
import Foundation
import Testing
@testable import ClaudeCodeAgent

/// The output of an agent is untrusted: no input may stop the decoder or
/// grow its memory without a limit.
@Suite struct ClaudeCodeHostileOutputTests {
    @Test func randomBytesGiveOnlyUnknownEventsWithBoundedLines() {
        var generator = SeededGenerator(seed: 0xBAD)
        var decoder = ClaudeCodeOutputDecoder(lineByteLimit: 4_096)
        var events: [ConversationEvent] = []
        for _ in 0..<200 {
            let count = Int.random(in: 0...2_000, using: &generator)
            events += decoder.decode((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
        }
        events += decoder.finish()
        #expect(events.count > 100)
        for event in events {
            guard case .unknown(let line) = event.kind else {
                Issue.record("Random bytes gave \(event.kind)")
                return
            }
            #expect(line.text.utf8.count <= SourceLine.byteLimit)
        }
    }

    @Test func oddJSONGivesEventsAndNoCrash() {
        let lines = [
            String(repeating: "[", count: 100_000), "{}", #"{"type":5}"#, #"{"type":"stream_event","event":{"type":"content_block_delta","index":1e300}}"#,
            #"{"type":"assistant","message":{"content":"text"}}"#, #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#,
            #"{"type":"result","usage":{"input_tokens":-1.5},"duration_ms":"x"}"#, #"{"type":"system","subtype":"permission_denied"}"#,
            #"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"seven_day":7}}}"#, "\u{0}\u{0}", #"{"type":"x\#u{0}"}"#,
        ]
        var decoder = ClaudeCodeOutputDecoder()
        let events = decoder.decode(Array(lines.joined(separator: "\n").utf8)) + decoder.finish()
        #expect(events.count >= lines.count)
        if case .unknown(let line) = events.first?.kind { #expect(line.reason == .notJSON) } else { Issue.record("Deep nesting gave an event") }
    }

    @Test func aStreamWithoutMessageStartKeepsItsTablesSmall() throws {
        var decoder = ClaudeCodeLineDecoder()
        for index in 0..<5_000 {
            let line = try JSONValue(decoding: Data(#"""
                {"type":"stream_event","event":{"type":"content_block_start","index":\#(index),"content_block":{"type":"tool_use","id":"t\#(index)","name":"Bash"}}}
                """#.utf8))
            _ = decoder.decode(line)
        }
        #expect(decoder.streamToolCalls.count <= 1_024)
        #expect(decoder.streamBlocks.count <= 1_024)
    }

    @Test func aLineOfManyMegabytesKeepsOnlyItsStart() {
        var decoder = ClaudeCodeOutputDecoder(lineByteLimit: 1_024 * 1_024)
        let piece = [UInt8](repeating: UInt8(ascii: "a"), count: 1_024 * 1_024)
        var events: [ConversationEvent] = []
        for _ in 0..<16 { events += decoder.decode(piece) }
        events += decoder.decode(Array("\n{\"type\":\"keep_alive\"}\n".utf8))
        #expect(events.map(\.kind) == [
            .unknown(UnknownLine(reason: .tooLong, text: String(repeating: "a", count: SourceLine.byteLimit), byteCount: 16 * 1_024 * 1_024)),
            .agentStatus(AgentStatus(kind: "keep_alive")),
        ])
    }
}
