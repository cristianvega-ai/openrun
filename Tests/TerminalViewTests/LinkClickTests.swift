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
