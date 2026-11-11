import AgentConversation
import Foundation
import Testing
@testable import ClaudeCodeAgent

@Suite struct ClaudeCodeUsageTests {
    @Test func eachUnifiedWindowBecomesAWindowWithItsLengthAndFraction() throws {
        let information = try JSONValue(decoding: Data(#"""
            {"status":"allowed","resetsAt":1794780000,"rateLimitType":"seven_day","overageStatus":"rejected",
             "isUsingOverage":false,"newField":[1],"unifiedWindows":{
              "seven_day":{"utilization":0.08,"resetsAt":1794780000,"status":"allowed"},
              "five_hour":{"utilization":0.5,"resetsAt":1794700000,"status":"allowed_warning"}}}
            """#.utf8))
        let reading = ClaudeCodeUsage.reading(from: information)
        #expect(reading.windows == [
            UsageWindow(name: "five_hour", lengthInMinutes: 300, usedFraction: 0.5,
                        resetTime: Date(timeIntervalSince1970: 1_794_700_000), status: "allowed_warning"),
            UsageWindow(name: "seven_day", lengthInMinutes: 10_080, usedFraction: 0.08,
                        resetTime: Date(timeIntervalSince1970: 1_794_780_000), status: "allowed"),
        ])
        #expect(reading.status == "allowed")
        #expect(Set(reading.otherFields.keys) == ["resetsAt", "rateLimitType", "overageStatus", "isUsingOverage", "newField"])
        #expect(reading.otherFields["newField"] == .array([.number(1)]))
    }

    @Test func anEventWithoutUnifiedWindowsGivesTheWindowThatItNames() throws {
        let information = try JSONValue(decoding: Data(#"{"status":"rejected","rateLimitType":"five_hour","utilization":1}"#.utf8))
        #expect(ClaudeCodeUsage.reading(from: information).windows == [
            UsageWindow(name: "five_hour", lengthInMinutes: 300, usedFraction: 1, status: "rejected"),
        ])
        #expect(ClaudeCodeUsage.reading(from: .null) == UsageReading(windows: []))
    }

    @Test func theNameOfAWindowGivesItsLength() {
        #expect(ClaudeCodeUsage.lengthInMinutes(ofWindowNamed: "seven_day_opus") == 10_080)
        #expect(ClaudeCodeUsage.lengthInMinutes(ofWindowNamed: "30_minutes") == 30)
        #expect(ClaudeCodeUsage.lengthInMinutes(ofWindowNamed: "one_week") == 10_080)
        #expect(ClaudeCodeUsage.lengthInMinutes(ofWindowNamed: "monthly") == nil)
        #expect(ClaudeCodeUsage.lengthInMinutes(ofWindowNamed: "seven_fortnight") == nil)
    }
}
