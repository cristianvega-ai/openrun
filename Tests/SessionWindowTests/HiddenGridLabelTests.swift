import AppKit
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite struct HiddenGridLabelTests {
    private func text(_ grid: (UInt16, UInt16), visible: (UInt16, UInt16)) -> String? {
        HiddenGridLabel.text(grid: TerminalSize(columns: grid.0, rows: grid.1), visible: TerminalSize(columns: visible.0, rows: visible.1))
    }

    @Test func theLabelNamesTheHiddenRowsAndColumns() {
        #expect(text((80, 64), visible: (80, 24)) == "40 rows hidden")
        #expect(text((100, 24), visible: (80, 24)) == "20 columns hidden")
        #expect(text((81, 25), visible: (80, 24)) == "1 row and 1 column hidden")
        #expect(text((60, 20), visible: (80, 24)) == nil)
    }

    @Test func theWindowShowsTheLabelForALargerGridOfTheSessionUntilItTakesItsSizeBack() async throws {
        let attachment = try FakeAttachment(size: TerminalView.estimatedGrid(for: SessionWindowController.contentSize, scale: NSScreen.main?.backingScaleFactor ?? 2))
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        let own = try #require(controller.view?.visibleGridSize)
        #expect(controller.hiddenGridLabel.isHidden && controller.hiddenGridLabel.superview === controller.window.contentView)
        attachment.deliver(.sizeChanged(SessionSize(columns: own.columns, rows: own.rows + 40)))
        await waitOnMainThread { !controller.hiddenGridLabel.isHidden }
        #expect(controller.hiddenGridLabel.stringValue == "40 rows hidden")
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(controller.hiddenGridLabel.isHidden)
    }
}
