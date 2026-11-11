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

    /// A long folder loses its start, so the model and the branch stay whole.
    @Test func aLongFolderLosesItsStartFirst() {
        let cell = SessionCellView()
        cell.show(SessionsListRow(SessionRowDisplay(identifier: UUID(), title: "Repair", folder: "~/Projects/openrun/Sources/TerminalRendering/Atlas",
                                                    branch: "main", kind: .agentThread(agent: "Codex", model: "Opus", account: nil),
                                                    lastActivity: now, startTime: now), now: now))
        cell.layoutSubtreeIfNeeded()
        #expect(cell.modelLabel.stringValue == "Opus · " && cell.branchLabel.stringValue == " · main")
        #expect(cell.folderLabel.lineBreakMode == .byTruncatingHead && !cell.place.isHidden && cell.secondLine.isHidden)
        #expect(cell.folderLabel.frame.width < cell.folderLabel.intrinsicContentSize.width)
        #expect(cell.branchLabel.frame.width >= cell.branchLabel.intrinsicContentSize.width)
        #expect(cell.place.frame.maxX <= cell.bounds.maxX - 18)
    }

    /// The age, the dot and the arc end at one edge and share the middle
    /// line of the title. The alignment rectangle of a label holds its text.
    @Test func theMarksShareOneEdgeAndOneMiddleLine() {
        let cell = SessionCellView()
        cell.show(row())
        cell.layoutSubtreeIfNeeded()
        let edge = cell.bounds.maxX - 18, middle = cell.title.frame.midY
        #expect(cell.age.alignmentRect(forFrame: cell.age.frame).maxX == edge)
        #expect(cell.attention.frame.maxX == edge && cell.progress.frame.maxX == edge)
        #expect(cell.age.frame.midY == middle && cell.attention.frame.midY == middle && cell.progress.frame.midY == middle)
        #expect(cell.attention.frame.size == cell.progress.frame.size)
    }
}
