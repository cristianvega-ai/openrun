import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor final class RecordingLinkOpener: LinkOpener {
    var targets: [URL] = []
    func open(_ target: URL) { targets.append(target) }
}

@MainActor @Suite struct LinkClickTests {
    private func makeClick(address: String = "https://example.com/docs") throws -> (LinkClick, RecordingLinkOpener) {
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 5), scrollbackLimit: 0)
        terminal.write("\u{1B}]8;;\(address)\u{07}link\u{1B}]8;;\u{07} plain")
        let click = LinkClick(terminal: terminal), opener = RecordingLinkOpener()
        click.opener = opener
        return (click, opener)
    }

    private func cell(_ column: UInt16) -> ViewportCell { ViewportCell(column: column, row: 0) }

    @Test func aCommandClickOpensTheLinkUnderThePointerOnRelease() throws {
        let (click, opener) = try makeClick()
        #expect(click.press(modifiers: .command, at: cell(1)) && click.isActive)
        #expect(opener.targets.isEmpty)
        click.release(at: cell(2))
        #expect(opener.targets == [URL(string: "https://example.com/docs")] && !click.isActive)
    }

    @Test func aHostThatShowsWebPagesTakesAWebLink() throws {
        let (click, opener) = try makeClick()
        var offered: [URL] = []
        click.webLinkAction = { offered.append($0); return $0.host == "example.com" }
        click.open("https://example.com/docs")
        click.open("https://other.example/x")
        #expect(offered.count == 2 && opener.targets == [URL(string: "https://other.example/x")])
    }

    @Test func aCommandClickOpensAPlainAddressAtOnceAndTheOscLinkWins() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 5), scrollbackLimit: 0)
        terminal.write("read https://example.com/plain. \u{1B}]8;;https://a.b/x\u{07}https://c.d\u{1B}]8;;\u{07}")
        let click = LinkClick(terminal: terminal), opener = RecordingLinkOpener()
        click.opener = opener
        #expect(!click.press(modifiers: [], at: cell(8)) && !click.press(modifiers: .command, at: cell(1)))
        #expect(click.press(modifiers: .command, at: cell(8)))
        click.release(at: cell(20))
        #expect(click.press(modifiers: .command, at: cell(34)))
        click.release(at: cell(35))
        // A release away from the address opens nothing.
        #expect(click.press(modifiers: .command, at: cell(8)))
        click.release(at: cell(2))
        #expect(opener.targets == [URL(string: "https://example.com/plain"), URL(string: "https://a.b/x")])
    }

    @Test func otherSchemesWaitForYesAndInvalidAddressesAreRejected() async throws {
        let address = "file:///tmp/example"
        let (click, opener) = try makeClick(address: address)
        var questions: [String] = []
        var answer: CheckedContinuation<Bool, Never>?
        click.ask = { text in
            questions.append(text)
            return await withCheckedContinuation { answer = $0 }
        }
        #expect(click.press(modifiers: .command, at: cell(0)))
        click.release(at: cell(1))
        await settle { answer != nil }
        #expect(questions == [address] && opener.targets.isEmpty)
        let first = try #require(answer)
        answer = nil
        first.resume(returning: false)
        await settle(seconds: 0.1) { false }
        #expect(opener.targets.isEmpty)
        #expect(click.press(modifiers: .command, at: cell(0)))
        click.release(at: cell(1))
        await settle { answer != nil }
        #expect(opener.targets.isEmpty)
        let second = try #require(answer)
        answer = nil
        second.resume(returning: true)
        await settle { !opener.targets.isEmpty }
        #expect(opener.targets == [URL(string: address)] && questions == [address, address])
        let (invalid, rejected) = try makeClick(address: "https://")
        #expect(!invalid.press(modifiers: .command, at: cell(0)) && rejected.targets.isEmpty)
    }

    @Test func aClickWithoutCommandOrOutsideALinkIsNotALinkClick() throws {
        let (click, opener) = try makeClick()
        #expect(!click.press(modifiers: [], at: cell(1)))
        #expect(!click.press(modifiers: .command, at: cell(6)))
        click.release(at: cell(1))
        #expect(opener.targets.isEmpty && !click.isActive)
    }

    @Test func aReleaseOutsideTheLinkOpensNothingAndEndsTheClick() throws {
        let (click, opener) = try makeClick()
        #expect(click.press(modifiers: .command, at: cell(0)))
        click.release(at: cell(8))
        #expect(opener.targets.isEmpty && !click.isActive)
    }
}

@MainActor @Suite struct LinkClickOfViewTests {
    private func makeView(_ output: String, address: String = "https://example.com/docs") throws -> (view: TerminalView, delegate: RecordingDelegate, opener: RecordingLinkOpener) {
        let view = try TerminalView()
        let delegate = RecordingDelegate(), opener = RecordingLinkOpener()
        (view.delegate, view.links.opener) = (delegate, opener)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutSubtreeIfNeeded()
        view.terminal.write("\u{1B}]8;;\(address)\u{07}link\u{1B}]8;;\u{07} plain" + output)
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
        #expect(opener.targets == [URL(string: "https://example.com/docs")])
    }

    @Test func theViewAsksItsDelegateWithoutSendingTheClickToTheProgram() async throws {
        let address = "file:///tmp/example"
        let (view, delegate, opener) = try makeView("\u{1B}[?1003h\u{1B}[?1006h", address: address)
        view.mouseDown(with: try event(.leftMouseDown, column: 1, in: view, .command))
        view.mouseUp(with: try event(.leftMouseUp, column: 1, in: view, .command))
        await settle { !delegate.linkQuestions.isEmpty }
        #expect(delegate.linkQuestions == [address] && delegate.takeSent() == "" && opener.targets.isEmpty)
        delegate.linkAnswer = true
        view.mouseDown(with: try event(.leftMouseDown, column: 1, in: view, .command))
        view.mouseUp(with: try event(.leftMouseUp, column: 1, in: view, .command))
        await settle { !opener.targets.isEmpty }
        #expect(delegate.linkQuestions == [address, address] && opener.targets == [URL(string: address)])
        #expect(delegate.takeSent() == "")
    }

    @Test func otherClicksGoToTheProgramAndOpenNoLink() throws {
        let (view, delegate, opener) = try makeView("\u{1B}[?1003h\u{1B}[?1006h")
        view.mouseDown(with: try event(.leftMouseDown, column: 1, in: view))
        view.mouseUp(with: try event(.leftMouseUp, column: 1, in: view))
        view.mouseDown(with: try event(.leftMouseDown, column: 8, in: view, .command))
        view.mouseUp(with: try event(.leftMouseUp, column: 8, in: view, .command))
        #expect(delegate.takeSent() == "\u{1B}[<0;2;1M\u{1B}[<0;2;1m\u{1B}[<0;9;1M\u{1B}[<0;9;1m" && opener.targets.isEmpty)
    }
}
