import AppKit
import Testing
@testable import SettingsWindow

/// The parts of a card: its rows with the lines between them, and the
/// row of one setting.
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

    @Test func aCardHoldsItsRowsOnARoundedSheet() {
        let card = SettingsCardView(rows: [NSView(), NSView()])
        card.frame = NSRect(x: 0, y: 0, width: SettingsCardView.width, height: 90)
        card.layoutSubtreeIfNeeded()
        #expect(card.rows.rows.count == 2 && card.rows.frame == card.bounds && card.subviews == [card.rows])
    }

    @Test func aRowHasTheNameAndTheNoteOfItsSettingAtTheLeftOfItsControl() {
        let control = NSSwitch()
        let row = SettingRowView(label: "Notifications", note: "macOS tells you.", control: control)
        #expect(row.label?.stringValue == "Notifications" && row.note?.stringValue == "macOS tells you." && row.arrangedSubviews.last === control)
        #expect(control.accessibilityLabel() == "Notifications" && row.fittingSize.height >= 44)
        // A long note goes on to more lines, and the row grows with it.
        let long = SettingRowView(label: "Option key", note: String(repeating: "An Option key that is not Alt. ", count: 4), control: NSSwitch())
        #expect(long.fittingSize.height > row.fittingSize.height + 10)
        // A row with no name starts with its note, and a row with no control gives its width to its words.
        let plain = SettingRowView(label: "", note: "An empty command starts your login shell.", control: nil)
        #expect(plain.label == nil && plain.arrangedSubviews.count == 1 && plain.note?.preferredMaxLayoutWidth == SettingsCardView.width - 28)
    }
}
