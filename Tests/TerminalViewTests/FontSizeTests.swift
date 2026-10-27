import AppKit
import Testing
import TerminalEmulation
@testable import TerminalView

@Suite struct FontSizeControlTests {
    @Test func theSizeStartsAt13PointsAndMovesByOnePoint() {
        var control = FontSizeControl()
        #expect(control.pointSize == 13)
        let larger = control.larger()
        #expect(larger && control.pointSize == 14)
        let smaller = control.smaller()
        #expect(smaller && control.pointSize == 13)
    }

    @Test func resetGoesBackTo13PointsAndTellsWhenNothingChanged() {
        var control = FontSizeControl()
        _ = control.larger()
        _ = control.larger()
        let reset = control.reset()
        let again = control.reset()
        #expect(reset && control.pointSize == 13)
        #expect(!again)
    }

    @Test func theSizeStopsAtTheLimits() {
        var control = FontSizeControl()
        for _ in 0..<100 { _ = control.larger() }
        let atLargest = control.larger()
        #expect(control.pointSize == 72 && !atLargest)
        for _ in 0..<100 { _ = control.smaller() }
        #expect(control.pointSize == 6)
    }
}

@MainActor private final class SizeDelegate: TerminalViewDelegate {
    var sizes: [TerminalSize] = []

    func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize) {
        sizes.append(size)
    }
}

@MainActor @Suite struct FontSizeOfViewTests {
    private func makeView() throws -> (view: TerminalView, delegate: SizeDelegate) {
        let view = try TerminalView()
        let delegate = SizeDelegate()
        view.delegate = delegate
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        return (view, delegate)
    }

    @Test func theActionsChangeTheFontAndTheGrid() throws {
        let (view, delegate) = try makeView()
        let first = view.gridSize
        view.increaseFontSize(nil)
        #expect(view.renderer.fonts.pointSize == 14)
        #expect(view.gridSize.columns < first.columns && delegate.sizes.last == view.gridSize)
        view.resetFontSize(nil)
        #expect(view.renderer.fonts.pointSize == 13 && view.gridSize == first)
        view.decreaseFontSize(nil)
        #expect(view.renderer.fonts.pointSize == 12 && view.gridSize.columns > first.columns)
    }
}
