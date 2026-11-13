import AppKit
import Testing
@testable import SettingsWindow

/// The parts of a card: its rows with the lines between them.
@MainActor @Suite struct SettingsCardViewTests {
    @Test func aLineStandsBetweenTwoRowsThatShow() {
        let rows = (0..<3).map { _ in NSView() }
        let view = SettingRowsView(rows: rows)
        #expect(view.rows == rows && view.arrangedSubviews.count == 5 && view.arrangedSubviews[1] is NSBox)
        // A search hides rows. No line stays at an edge or beside a row that does not show.
        rows[0].isHidden = true
        view.refreshLines()
        #expect(view.arrangedSubviews[1].isHidden && !view.arrangedSubviews[3].isHidden)
        (rows[0].isHidden, rows[2].isHidden) = (false, true)
        view.refreshLines()
        #expect(!view.arrangedSubviews[1].isHidden && view.arrangedSubviews[3].isHidden)
        view.show([rows[1]])
        #expect(view.arrangedSubviews == [rows[1]] && rows[0].superview == nil)
    }
}
