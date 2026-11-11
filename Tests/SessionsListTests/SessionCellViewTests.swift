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

    private func place(_ folder: String, model: String?) -> SessionsListRow {
        let kind: SessionKind = model.map { .agentThread(agent: "Codex", model: $0, account: nil) } ?? .terminal
        return SessionsListRow(SessionRowDisplay(identifier: UUID(), title: "Repair", folder: folder, branch: "main", kind: kind,
                                                 lastActivity: now, startTime: now), now: now)
    }

    /// The second line starts at the title and reads without a gap. A long
    /// line loses only the start of its folder, and its spare room is at its end.
    @Test func theSecondLineStartsAtTheTitleAndCutsOnlyTheFolder() {
        let long = "~/Projects/openrun/Sources/TerminalRendering/Glyphs/Atlas"
        let cases: [(String, String?, String)] = [("~/p", "Opus", "Opus · ~/p · main"), ("~/p", nil, "~/p · main"),
                                                  (long, "Opus", "Opus · …"), (long, nil, "…")]
        for (folder, model, start) in cases {
            let cell = SessionCellView()
            cell.show(place(folder, model: model))
            cell.layoutSubtreeIfNeeded()
            let line = cell.secondLine
            #expect(line.frame.minX == cell.title.frame.minX && line.alignment == .natural && !line.isHidden)
            #expect(line.stringValue.hasPrefix(start) && line.stringValue.hasSuffix("Atlas · main") == (folder == long))
            #expect(line.intrinsicContentSize.width <= line.frame.width, "\(line.stringValue)")
        }
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
