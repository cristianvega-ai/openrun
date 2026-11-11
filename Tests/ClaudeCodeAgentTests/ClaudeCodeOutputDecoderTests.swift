import AgentConversation
import ClaudeCodeAgent
import Foundation
import Testing

@Suite struct ClaudeCodeOutputDecoderTests {
    @Test(arguments: Fixture.turns)
    func eachLineOfARecordedTurnGivesKnownEventsThatCarryTheLine(name: String) throws {
        let fixture = Fixture(name: name)
        let lines = try String(decoding: fixture.bytes, as: UTF8.self).split(separator: "\n")
        var decoder = ClaudeCodeOutputDecoder()
        for line in lines {
            let events = decoder.decode(Array((line + "\n").utf8))
            #expect(!events.isEmpty)
            #expect(events.allSatisfy { $0.sourceLine == SourceLine(bytes: Array(line.utf8)) })
            #expect(events.allSatisfy { if case .unknown = $0.kind { false } else { true } }, "\(line.prefix(80))")
        }
    }

    @Test func aPlainTurnGivesTheUserMessageTheAnswerAndTheEnd() throws {
        let transcript = try Fixture(name: "plain-turn").transcript
        #expect(transcript.items.map(\.content) == [
            .userMessage(UserMessage(
                identifier: "00000000-0000-4000-8000-000000000001", text: "Reply with the single word ok.", isAccepted: true)),
            .agentMessage(AgentMessage(text: "ok", isComplete: true)),
            .turnEnd(TurnEnd(
                outcome: .done,
                usage: TokenUsage(inputTokens: 2, outputTokens: 4, cacheReadInputTokens: 11_384, cacheCreationInputTokens: 11_914),
                durationMilliseconds: 1_271, serviceDurationMilliseconds: 1_200, estimatedCostInDollars: 0.00249884)),
        ])
        #expect(transcript.items[1].identifier == "text:msg_01Fixture00000000000001:0")
        #expect(transcript.state == .finishedTurn)
        #expect(transcript.agentStart == AgentStart(
            conversationIdentifier: "00000000-0000-4000-8000-000000000003", model: "claude-haiku-5-5",
            permissionMode: "default", agentVersion: "2.1.322", workingFolder: "/work/project"))
        #expect(transcript.usage?.windows.map(\.usedFraction) == [0.08])
    }

    @Test func linesThatThisVersionCannotReadBecomeUnknownEventsAndTheStreamGoesOn() {
        var decoder = ClaudeCodeOutputDecoder(lineByteLimit: 64)
        let input = "not json\n[1]\n{\"type\":\"future\",\"subtype\":\"kind\"}\n{\"type\":\"system\",\"subtype\":\"new\"}\n"
            + String(repeating: "x", count: 100) + "\n{\"type\":\"rate_limit_event\"}\n{\"type\":\"res"
        let events = decoder.decode(Array(input.utf8)) + decoder.finish()
        #expect(events.map(\.kind) == [
            .unknown(UnknownLine(reason: .notJSON, text: "not json", byteCount: 8)),
            .unknown(UnknownLine(reason: .notJSON, text: "[1]", byteCount: 3)),
            .unknown(UnknownLine(reason: .unknownKind, kind: "future/kind", text: #"{"type":"future","subtype":"kind"}"#, byteCount: 34)),
            .unknown(UnknownLine(reason: .unknownKind, kind: "system/new", text: #"{"type":"system","subtype":"new"}"#, byteCount: 33)),
            .unknown(UnknownLine(reason: .tooLong, text: String(repeating: "x", count: 100), byteCount: 100)),
            .usage(UsageReading(windows: [])),
            .unknown(UnknownLine(reason: .cutShort, text: #"{"type":"res"#, byteCount: 12)),
        ])
    }
}
