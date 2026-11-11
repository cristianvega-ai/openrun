import Foundation
import Testing
import SessionsList

@Suite struct SessionsArrangementTests {
    private func row(_ title: String, inProgress: Bool = false, active: TimeInterval, started: TimeInterval) -> SessionRowDisplay {
        SessionRowDisplay(identifier: UUID(), title: title, detail: "", kind: .terminal, isInProgress: inProgress,
                          lastActivity: Date(timeIntervalSince1970: active), startTime: Date(timeIntervalSince1970: started))
    }

    @Test func theFiltersSplitTheRowsByProgress() {
        let rows = [row("build", inProgress: true, active: 1, started: 1), row("shell", active: 2, started: 2)]
        #expect(rows.filter(SessionsFilter.all.includes).count == 2)
        #expect(rows.filter(SessionsFilter.inProgress.includes).map(\.title) == ["build"])
        #expect(rows.filter(SessionsFilter.finished.includes).map(\.title) == ["shell"])
        #expect(SessionsFilter.allCases.map(\.title) == ["All", "In Progress", "Finished"])
    }

    /// A row that needs the user keeps its place in the filter of its progress.
    @Test func anAlertDoesNotChangeTheFilter() {
        var waiting = row("agent", active: 1, started: 1)
        waiting.alert = "Claude needs your permission"
        #expect(SessionsFilter.finished.includes(waiting) && !SessionsFilter.inProgress.includes(waiting))
    }
}
