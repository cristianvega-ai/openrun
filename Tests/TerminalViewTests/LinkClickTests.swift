import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor final class RecordingLinkOpener: LinkOpener {
    var urls: [URL] = []
    func open(_ url: URL) { urls.append(url) }
}

@MainActor @Suite struct LinkClickTests {
    private func makeClick() throws -> (LinkClick, RecordingLinkOpener) {
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 5), scrollbackLimit: 0)
        terminal.write("\u{1B}]8;;https://example.com/docs\u{07}link\u{1B}]8;;\u{07} plain")
        let click = LinkClick(terminal: terminal), opener = RecordingLinkOpener()
        click.opener = opener
        return (click, opener)
    }

    private func cell(_ column: UInt16) -> ViewportCell { ViewportCell(column: column, row: 0) }

    @Test func aCommandClickOpensTheLinkUnderThePointerOnRelease() throws {
        let (click, opener) = try makeClick()
        #expect(click.press(modifiers: .command, at: cell(1)) && click.isActive)
        #expect(opener.urls.isEmpty)
        click.release(at: cell(2))
        #expect(opener.urls == [URL(string: "https://example.com/docs")] && !click.isActive)
    }

    @Test func aClickWithoutCommandOrOutsideALinkIsNotALinkClick() throws {
        let (click, opener) = try makeClick()
        #expect(!click.press(modifiers: [], at: cell(1)))
        #expect(!click.press(modifiers: .command, at: cell(6)))
        click.release(at: cell(1))
        #expect(opener.urls.isEmpty && !click.isActive)
    }

    @Test func aReleaseOutsideTheLinkOpensNothingAndEndsTheClick() throws {
        let (click, opener) = try makeClick()
        #expect(click.press(modifiers: .command, at: cell(0)))
        click.release(at: cell(8))
        #expect(opener.urls.isEmpty && !click.isActive)
    }
}

@MainActor @Suite struct LinkClickOfViewTests {
    private func makeView(_ output: String) throws -> (view: TerminalView, delegate: RecordingDelegate, opener: RecordingLinkOpener) {
        let view = try TerminalView()
        let delegate = RecordingDelegate(), opener = RecordingLinkOpener()
        (view.delegate, view.links.opener) = (delegate, opener)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutSubtreeIfNeeded()
        view.terminal.write("\u{1B}]8;;https://example.com/docs\u{07}link\u{1B}]8;;\u{07} plain" + output)
        return (view, delegate, opener)
    }

    /// A mouse event in a column of row 0.
    private func event(_ type: NSEvent.EventType, column: Int, in view: TerminalView, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let cell = view.cellSize, padding = view.gridPadding
        let point = NSPoint(x: padding + (CGFloat(column) + 0.5) * cell.width, y: view.bounds.height - padding - 0.5 * cell.height)
        return try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: flags, timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func aCommandClickOnALinkGoesOnlyToTheLinkAlsoWhenTheProgramReadsTheMouse() throws {
        let (view, delegate, opener) = try makeView("\u{1B}[?1003h\u{1B}[?1006h")
        view.mouseDown(with: try event(.leftMouseDown, column: 1, in: view, .command))
        view.mouseDragged(with: try event(.leftMouseDragged, column: 2, in: view, .command))
        view.mouseUp(with: try event(.leftMouseUp, column: 2, in: view, .command))
        #expect(delegate.takeSent() == "" && !view.terminal.hasSelection)
        #expect(opener.urls == [URL(string: "https://example.com/docs")])
    }

    @Test func otherClicksGoToTheProgramAndOpenNoLink() throws {
        let (view, delegate, opener) = try makeView("\u{1B}[?1003h\u{1B}[?1006h")
        view.mouseDown(with: try event(.leftMouseDown, column: 1, in: view))
        view.mouseUp(with: try event(.leftMouseUp, column: 1, in: view))
        view.mouseDown(with: try event(.leftMouseDown, column: 8, in: view, .command))
        view.mouseUp(with: try event(.leftMouseUp, column: 8, in: view, .command))
        #expect(delegate.takeSent() == "\u{1B}[<0;2;1M\u{1B}[<0;2;1m\u{1B}[<0;9;1M\u{1B}[<0;9;1m" && opener.urls.isEmpty)
    }
}
