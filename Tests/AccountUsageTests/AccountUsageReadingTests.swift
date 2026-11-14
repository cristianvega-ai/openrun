import AccountUsage
import Foundation
import SessionProtocol
import Testing

@Suite struct AccountUsageReadingTests {
    private func reading(_ agent: String, _ account: String?, at seconds: Double) -> AccountUsageReading {
        AccountUsageReading(agent: agent, account: account, windows: [ThreadUsageWindow(name: "seven_day", usedFraction: seconds / 1_000)], readAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func eachAccountKeepsItsNewestReading() {
        let readings = [
            reading("claude-code", nil, at: 100), reading("claude-code", "Work", at: 50), reading("claude-code", nil, at: 300),
            reading("codex", nil, at: 200), reading("claude-code", nil, at: 150),
        ]
        // The account of the login shell and a named account of one agent are two accounts, and so are two agents.
        let newest = AccountUsageReading.newest(readings)
        #expect(newest == [reading("claude-code", nil, at: 300), reading("claude-code", "Work", at: 50), reading("codex", nil, at: 200)])
    }
}
