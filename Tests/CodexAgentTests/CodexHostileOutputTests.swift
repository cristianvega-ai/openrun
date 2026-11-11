import AgentConversation
import Testing
@testable import CodexAgent

/// The output of the app-server is untrusted: no input may stop the reader
/// or the mapper, or grow their memory without a limit.
@Suite struct CodexHostileOutputTests {
    @Test func randomBytesGiveOnlyUnknownEventsWithBoundedLines() {
        var generator = SeededGenerator(seed: 0xBAD)
        var pieces: [ArraySlice<UInt8>] = []
        for _ in 0..<200 {
            let count = Int.random(in: 0...2_000, using: &generator)
            pieces.append((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }[...])
        }
        let events = CodexFixture.events(of: pieces)
        #expect(events.count > 100)
        for event in events {
            guard case .unknown(let line) = event else {
                Issue.record("Random bytes gave \(event)")
                return
            }
            #expect(line.text.utf8.count <= SourceLine.byteLimit)
        }
    }

    @Test func oddMessagesGiveEventsAndNoCrash() {
        let big = "9000000000000000000"
        let lines = [
            String(repeating: "[", count: 100_000), "{}", #"{"method":5}"#, #"{"id":{},"result":1}"#, #"{"method":"turn/completed","params":7}"#,
            #"{"method":"thread/tokenUsage/updated","params":{"tokenUsage":{"total":{"inputTokens":-\#(big),"cachedInputTokens":\#(big)}}}}"#,
            #"{"method":"turn/started","params":{"turn":{"id":1e300}}}"#,
            #"{"method":"thread/tokenUsage/updated","params":{"tokenUsage":{"total":{"inputTokens":\#(big),"outputTokens":1e300}}}}"#,
            #"{"method":"turn/completed","params":{"turn":{"status":["x"],"error":{"codexErrorInfo":{}}}}}"#,
            #"{"method":"item/completed","params":{"item":{"type":"fileChange","changes":[{"kind":"add","diff":5},7]}}}"#,
            #"{"method":"item/started","params":{"item":{"type":"userMessage","content":"text"}}}"#,
            #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"windowDurationMins":-1,"usedPercent":"x"}}}}"#,
        ]
        let events = CodexFixture.events(of: [Array(lines.joined(separator: "\n").utf8)[...]])
        #expect(events.count >= lines.count - 2)
        #expect(events.first == .unknown(UnknownLine(reason: .notJSON, text: String(repeating: "[", count: SourceLine.byteLimit),
                                                     byteCount: 100_000)))
    }

    @Test func declinesThatNeverCompleteKeepTheirTableSmall() {
        var mapper = CodexEventMapper()
        for index in 0..<5_000 { mapper.noteDecline(of: "item\(index)", reason: .unanswered) }
        #expect(mapper.declineReasons.count <= CodexEventMapper.declineLimit)
    }
}
