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

@MainActor @Suite struct FontSizeOfViewTests {
    private func makeView() throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
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

    private func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
    }

    @Test func aNewScaleMakesNewCellsForTheSameView() throws {
        let (view, _) = try makeView()
        let cellWidth = view.renderer.fonts.cellWidth
        view.rebuildRenderer(scale: 1)
        #expect(view.renderer.fonts.scale == 1 && view.layer?.contentsScale == 1)
        #expect(view.renderer.fonts.cellWidth == cellWidth / 2 && view.renderer.padding == 8)
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func theKeysOfCommandChangeTheFont() throws {
        let (view, _) = try makeView()
        let window = showFocused(view)
        defer { window.close() }
        #expect(view.performKeyEquivalent(with: try key("=", .command)))
        #expect(view.performKeyEquivalent(with: try key("+", [.command, .shift])))
        #expect(view.renderer.fonts.pointSize == 15)
        #expect(view.performKeyEquivalent(with: try key("-", .command)))
        #expect(view.renderer.fonts.pointSize == 14)
        #expect(view.performKeyEquivalent(with: try key("0", .command)))
        #expect(view.renderer.fonts.pointSize == 13)
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func otherKeysAreNotForTheFont() throws {
        let (view, _) = try makeView()
        let window = showFocused(view)
        defer { window.close() }
        // A key with Command and no font action goes to the program, and the view takes it.
        #expect(view.performKeyEquivalent(with: try key("=", [.command, .option])))
        #expect(!view.performKeyEquivalent(with: try key("=", [])))
        #expect(view.performKeyEquivalent(with: try key("c", .command)))
        #expect(view.renderer.fonts.pointSize == 13)
    }
}
