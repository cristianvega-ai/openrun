import AgentConversation
import Foundation
import Testing
@testable import CodexAgent

@Suite struct CodexUsageTests {
    /// The rate limits as Codex 0.167.0 gave them, with a made-up plan and
    /// balance.
    let limits = #"""
        {"limitId":"codex","limitName":null,"primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1700270891},
         "secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"100.0000000000"},
         "spendControlReached":false,"planType":"plus","rateLimitReachedType":null}
        """#

    @Test func theWeeklyWindowTakesItsNameFromItsLength() throws {
        let reading = CodexUsage.reading(from: try JSONValue(decoding: Data(limits.utf8)))
        #expect(reading.windows == [UsageWindow(
            name: "seven_day", lengthInMinutes: 10_080, usedFraction: 0.04, resetTime: Date(timeIntervalSince1970: 1_700_270_891))])
        #expect(reading.status == nil)
        #expect(reading.otherFields["limitId"] == .string("codex"))
        #expect(reading.otherFields["planType"] == .string("plus"))
        #expect(reading.otherFields["primary"] == nil)
    }

    @Test func aReachedLimitIsTheStateOfTheReading() throws {
        let reached = limits.replacingOccurrences(of: #""rateLimitReachedType":null"#, with: #""rateLimitReachedType":"rate_limit_reached""#)
        #expect(CodexUsage.reading(from: try JSONValue(decoding: Data(reached.utf8))).status == "rate_limit_reached")
    }

    @Test func aWindowOfAnyLengthHasAName() {
        #expect(CodexUsage.name(ofWindowWithLength: 300) == "5_hour")
        #expect(CodexUsage.name(ofWindowWithLength: 1_440) == "1_day")
        #expect(CodexUsage.name(ofWindowWithLength: 45) == "45_minute")
        let unnamed = CodexUsage.reading(from: .object(["secondary": .object(["usedPercent": .number(50)])]))
        #expect(unnamed.windows == [UsageWindow(name: "secondary", usedFraction: 0.5)])
    }
}
