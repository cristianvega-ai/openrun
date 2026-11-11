import AppKit
import PaneAppearance
import Testing
@testable import MainWindow

@MainActor @Suite struct PaneWindowTests {
    @Test func theWindowHasNoTitleStripAndItsLightsSitOnTheMiddleOfATopRow() throws {
        _ = NSApplication.shared
        let window = PaneWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500))
        defer { window.close() }
        #expect(window.styleMask.contains(.fullSizeContentView) && window.titlebarAppearsTransparent && window.titleVisibility == .hidden)
        #expect(window.tabbingMode == .disallowed && window.title == "OpenRun")
        let close = try #require(window.standardWindowButton(.closeButton))
        let middle = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: nil)
        #expect(abs(window.contentLayoutRect.maxY + (window.frame.height - window.contentLayoutRect.maxY) - middle.y - PaneTopRow.height / 2) < 1)
        #expect(window.trafficLightsSpace > 60 && window.trafficLightsSpace < 100)
    }

    @Test func theHostHearsOfEachChangeOfTheFocus() {
        _ = NSApplication.shared
        let window = PaneWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        defer { window.close() }
        let field = NSTextField()
        window.contentView?.addSubview(field)
        var changes = 0
        window.firstResponderChanged = { changes += 1 }
        // A text field passes the focus on to its field editor, which is a second change.
        window.makeFirstResponder(field)
        let afterField = changes
        window.makeFirstResponder(nil)
        #expect(afterField >= 1 && changes > afterField && window.firstResponder === window)
    }
}
