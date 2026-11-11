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

    @Test func eachOrderArrangesTheRows() {
        let rows = [row("b 10", active: 5, started: 1), row("a", active: 9, started: 3), row("b 9", active: 7, started: 2)]
        #expect(SessionsOrder.manual.arranged(rows).map(\.title) == ["b 10", "a", "b 9"])
        #expect(SessionsOrder.lastActivity.arranged(rows).map(\.title) == ["a", "b 9", "b 10"])
        #expect(SessionsOrder.startTime.arranged(rows).map(\.title) == ["a", "b 9", "b 10"])
        #expect(SessionsOrder.name.arranged(rows).map(\.title) == ["a", "b 9", "b 10"])
    }

    @Test func equalRowsKeepTheUsersOrder() {
        let rows = [row("x", active: 1, started: 1), row("y", active: 1, started: 1), row("x", active: 1, started: 1)]
        for order in SessionsOrder.allCases {
            #expect(order.arranged(rows).map(\.identifier) == (order == .name ? [rows[0], rows[2], rows[1]] : rows).map(\.identifier))
        }
    }
}
