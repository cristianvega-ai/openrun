import AppKit
import Foundation
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionCellViewTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func row(inProgress: Bool = false, alert: String? = nil) -> SessionsListRow {
        SessionsListRow(SessionRowDisplay(identifier: UUID(), title: "Repair the resize", folder: "~/p", branch: "main",
                                          kind: .agentThread(agent: "Codex", model: nil, account: nil), isInProgress: inProgress,
                                          alert: alert, lastActivity: now - 300, startTime: now), now: now)
    }

    @Test func eachStateShowsOneMark() {
        let cell = SessionCellView()
        cell.show(row())
        #expect(cell.title.stringValue == "Repair the resize" && cell.secondLine.stringValue == "~/p · main")
        #expect(cell.age.stringValue == "5m" && !cell.age.isHidden && cell.attention.isHidden && cell.progress.isHidden)
        cell.show(row(inProgress: true))
        #expect(cell.age.isHidden && cell.attention.isHidden && !cell.progress.isHidden)
        cell.show(row(alert: "Approve the edit?"))
        #expect(cell.age.isHidden && !cell.attention.isHidden && cell.progress.isHidden)
        #expect(cell.secondLine.stringValue == "Approve the edit?" && cell.icon.image != nil)
        #expect(cell.accessibilityLabel() == "Repair the resize, Approve the edit?, needs you")
    }
}
