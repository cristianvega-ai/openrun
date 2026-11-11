import AppKit
import Testing
@testable import PaneAppearance

@MainActor @Suite struct SelectedRowViewTests {
    @Test func theSelectionIsQuieterWhenTheWindowIsNotKey() {
        #expect(SelectedRowView.selectionColor(windowIsKey: true) == PaneColor.rowSelection)
        #expect(SelectedRowView.selectionColor(windowIsKey: false) == PaneColor.inactiveRowSelection)
        #expect(SelectedRowView().interiorBackgroundStyle == .normal)
    }
}
