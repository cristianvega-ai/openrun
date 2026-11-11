import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct PaneSplitViewTests {
    /// NSSplitView tracks a drag inside mouseDown, so the hooks wrap the call.
    @Test func aClickTellsTheStartAndTheEndOfADrag() throws {
        let splitView = PaneSplitView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var calls: [String] = []
        (splitView.dragStarted, splitView.dragEnded) = ({ calls.append("start") }, { calls.append("end") })
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        splitView.mouseDown(with: event)
        #expect(calls == ["start", "end"])
    }
}
