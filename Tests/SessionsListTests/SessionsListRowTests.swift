import Foundation
import Testing
@testable import SessionsList

@Suite struct SessionsListRowTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func display(_ kind: SessionKind, inProgress: Bool = false, alert: String? = nil, minutesAgo: Double = 0) -> SessionRowDisplay {
        SessionRowDisplay(identifier: UUID(), title: "Repair the resize", detail: "~/Projects/openrun · main", kind: kind,
                          isInProgress: inProgress, alert: alert, lastActivity: now - minutesAgo * 60, startTime: now)
    }

    @Test func aThreadShowsItsAgentModelAndAccountQuietly() {
        let row = SessionsListRow(display(.agentThread(agent: "Claude Code", model: "Opus", account: "Work"), inProgress: true), now: now)
        #expect(row.secondLine == "Claude Code · Opus · Work · ~/Projects/openrun · main")
        #expect(row.symbol == "bubble.left" && row.mark == .progress)
        #expect(row.accessibilityLabel == "Repair the resize, Claude Code · Opus · Work · ~/Projects/openrun · main, in progress")
        let plain = SessionsListRow(display(.agentThread(agent: "Codex", model: nil, account: nil)), now: now)
        #expect(plain.secondLine == "Codex · ~/Projects/openrun · main")
    }

    @Test func anAlertTakesThePlaceOfTheSecondLine() {
        let row = SessionsListRow(display(.terminal, inProgress: true, alert: "Build failed"), now: now)
        #expect(row.secondLine == "Build failed" && row.mark == .attention && row.symbol == "terminal")
        #expect(row.accessibilityLabel == "Repair the resize, terminal, Build failed, needs you")
    }

    @Test func aFinishedRowShowsItsAge() {
        #expect(SessionsListRow(display(.terminal, minutesAgo: 90), now: now).mark == .age("1h"))
        let minutes: [Double] = [0.5, 5, 59, 60, 1380, 1440, 8640, 10080, 43200]
        let ages = minutes.map { SessionsListRow.age(of: now.addingTimeInterval(-60 * $0), now: now) }
        #expect(ages == ["now", "5m", "59m", "1h", "23h", "1d", "6d", "1w", "4w"])
        #expect(SessionsListRow.age(of: now + 60, now: now) == "now")
    }
}
