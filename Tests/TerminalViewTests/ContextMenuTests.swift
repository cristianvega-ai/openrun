import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct ContextMenuTests {
    private func makeView() throws -> (view: TerminalView, pasteboard: FakePasteboard, opener: RecordingLinkOpener) {
        let view = try TerminalView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        view.layoutSubtreeIfNeeded()
        let pasteboard = FakePasteboard(), opener = RecordingLinkOpener()
        (view.pasteboard, view.links.opener) = (pasteboard, opener)
        return (view, pasteboard, opener)
    }

    /// A right click on a cell of the first row.
    private func rightClick(on view: TerminalView, column: Double, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let location = view.pointerLocation
        let point = CGPoint(x: location.padding + (column + 0.5) * location.cellSize.width, y: view.bounds.height - location.padding - 2)
        return try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func theMenuOffersCopyOnlyWithASelectionAndAlwaysPasteAndSelectAll() throws {
        let (view, _, _) = try makeView()
        view.terminal.write("hello world")
        #expect(view.menu(for: try rightClick(on: view, column: 1))?.items.map(\.title) == ["Paste", "", "Select All"])
        try view.terminal.selectWord(at: ViewportCell(column: 1, row: 0))
        #expect(view.menu(for: try rightClick(on: view, column: 1))?.items.map(\.title) == ["Copy", "Paste", "", "Select All"])
    }

    @Test func overALinkTheMenuOpensAndCopiesIt() throws {
        let (view, pasteboard, opener) = try makeView()
        view.terminal.write("see https://example.com/x.")
        let menu = try #require(view.menu(for: try rightClick(on: view, column: 8)))
        #expect(menu.items.map(\.title) == ["Open Link", "Copy Link", "", "Paste", "", "Select All"])
        for item in menu.items.prefix(2) { _ = (item.target as? NSObject)?.perform(item.action, with: item) }
        #expect(opener.targets == [URL(string: "https://example.com/x")] && pasteboard.text == "https://example.com/x")
    }

    @Test func aProgramThatReadsTheMouseGetsTheRightClickUnlessShiftIsDown() throws {
        let (view, _, _) = try makeView()
        view.terminal.write("\u{1B}[?1000h")
        #expect(view.menu(for: try rightClick(on: view, column: 1)) == nil)
        #expect(view.menu(for: try rightClick(on: view, column: 1, .shift)) != nil)
    }
}
