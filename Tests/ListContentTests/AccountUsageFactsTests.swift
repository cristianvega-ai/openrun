import Foundation
import ProjectsList
import SessionOverview
import SessionProtocol
import Testing
import WindowLayout
@testable import ListContent

@Suite struct AccountUsageFactsTests {
    private let zone = TimeZone(identifier: "UTC")!

    private func thread(_ agent: String, account: String? = nil, used: Double?, readAt seconds: Double?, status: String? = nil) -> ThreadSummary {
        var thread = ThreadSummary(
            identifier: UUID(), agent: agent, folder: "/work", model: "opus", permissionMode: "default", accountName: account,
            createdAt: Date(timeIntervalSince1970: 0), lastActivityAt: Date(timeIntervalSince1970: 0), state: "idle", isProcessRunning: false,
            waitingMessageCount: 0)
        thread.usageReadAt = seconds.map { Date(timeIntervalSince1970: $0) }
        thread.usageWindows = [
            ThreadUsageWindow(name: "five_hour", lengthInMinutes: 300), ThreadUsageWindow(
                name: "seven_day", lengthInMinutes: 10_080, usedFraction: used, resetTime: Date(timeIntervalSince1970: 86_400), status: status),
        ]
        return thread
    }

    @Test func eachAccountShowsTheNewestReadingOfItsThreads() {
        let threads = [
            thread("codex", account: "Work", used: 0.8, readAt: 300), thread("claude-code", used: 0.2, readAt: 100),
            thread("claude-code", used: 0.376, readAt: 200), thread("claude-code", account: "Work", used: 1, readAt: 50, status: "rejected"),
            // A thread with no reading, or with no used part, shows nothing.
            thread("codex", used: 0.5, readAt: nil), thread("codex", used: nil, readAt: 400),
        ]
        let displays = AccountUsageFacts.displays(of: threads, timeZone: zone)
        #expect(displays.map(\.title) == ["Claude Code", "Claude Code · Work", "Codex · Work"])
        #expect(displays.map(\.windows) == [
            [.init(name: "Week", usedFraction: 0.376)], [.init(name: "Week", usedFraction: 1, isAtLimit: true)], [.init(name: "Week", usedFraction: 0.8)],
        ])
        #expect(displays[0].help.hasPrefix("Claude Code: Week 38% used, resets Friday") && displays[0].help.contains(". Read at "))
        #expect(displays[0].readTime.contains("03") && !displays[0].readTime.contains("Friday"))
        // The first pane gets them with its projects.
        let content = ListContent(overview: SessionOverview(threads: threads), layout: WindowLayout(), inView: nil)
        #expect(content.projects.accounts.map(\.title) == displays.map(\.title))
    }
}
