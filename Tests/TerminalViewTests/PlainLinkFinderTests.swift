import Testing
import TerminalEmulation
import TerminalRendering
@testable import TerminalView

@Suite struct PlainLinkFinderTests {
    private func link(_ output: String, column: UInt16, row: UInt32 = 0, columns: UInt16 = 40) throws -> PlainLink? {
        let terminal = try Terminal(size: TerminalSize(columns: columns, rows: 4), scrollbackLimit: 0)
        terminal.write(output)
        return PlainLinkFinder.link(at: ViewportCell(column: column, row: row), in: terminal)
    }

    @Test func anAddressUnderTheCellIsFoundWithItsCells() throws {
        let found = try #require(try link("see https://example.com/a?b=1 now", column: 10))
        #expect(found == PlainLink(address: "https://example.com/a?b=1", runs: [ViewportCellRun(row: 0, columns: 4..<29)]))
        #expect(try link("see https://example.com/a now", column: 1) == nil)
        #expect(try link("see https://example.com/a now", column: 30) == nil)
        #expect(try link("plain http://a.b", column: 8)?.address == "http://a.b")
    }

    @Test func trailingPunctuationAndClosingBracketsStayOutside() throws {
        #expect(try link("Go to https://a.b/c.", column: 8)?.address == "https://a.b/c")
        #expect(try link("(see https://a.b/c), then", column: 8)?.address == "https://a.b/c")
        #expect(try link("[https://a.b/c]", column: 3)?.address == "https://a.b/c")
        #expect(try link("https://en.wikipedia.org/wiki/A_(B)", column: 3)?.address == "https://en.wikipedia.org/wiki/A_(B)")
        #expect(try link("'https://a.b/c'", column: 3)?.address == "https://a.b/c")
        #expect(try link("<https://a.b/c>", column: 3)?.address == "https://a.b/c")
    }

    @Test func anAddressThatWrapsOntoTheNextRowIsWhole() throws {
        let output = "abcdef https://example.com/a/long/path end"
        let fromSecondRow = try #require(try link(output, column: 2, row: 1, columns: 20))
        #expect(fromSecondRow.address == "https://example.com/a/long/path")
        #expect(fromSecondRow.runs == [ViewportCellRun(row: 0, columns: 7..<20), ViewportCellRun(row: 1, columns: 0..<18)])
        #expect(try link(output, column: 9, columns: 20) == fromSecondRow)
    }

    @Test func anAddressThatGoesOnOutsideTheViewportIsNoLink() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 13, rows: 2), scrollbackLimit: 100)
        // 52 characters fill four rows of 13 columns, and a short line follows.
        terminal.write("https://a.b/" + String(repeating: "x", count: 40) + "\r\nend")
        terminal.scrollViewport(.byRows(-3))
        #expect(terminal.viewportRowText(at: 0)?.cells.prefix(5).joined() == "https")
        #expect(PlainLinkFinder.link(at: ViewportCell(column: 2, row: 0), in: terminal) == nil)
        #expect(PlainLinkFinder.link(at: ViewportCell(column: 2, row: 1), in: terminal) == nil)
        terminal.scrollViewport(.byRows(2))
        #expect(PlainLinkFinder.link(at: ViewportCell(column: 2, row: 0), in: terminal) == nil)
        // With the whole line in view, the whole address is the link.
        try terminal.resize(to: TerminalSize(columns: 13, rows: 5))
        terminal.scrollViewport(.toBottom)
        let row = try #require((0..<5).first { terminal.viewportRowText(at: UInt32($0))?.cells.prefix(5).joined() == "https" })
        #expect(PlainLinkFinder.link(at: ViewportCell(column: 2, row: UInt32(row) + 1), in: terminal)?.address.count == 52)
    }

    @Test func wideCharactersBeforeTheAddressKeepTheColumns() throws {
        let found = try #require(try link("日本 https://a.b/日 x", column: 6))
        #expect(found.address == "https://a.b/" && found.runs == [ViewportCellRun(row: 0, columns: 5..<17)])
    }

    @Test func otherSchemesAndAddressesWithNoHostAreNotLinks() throws {
        #expect(try link("ftp://a.b/c file:///etc/hosts", column: 3) == nil)
        #expect(try link("ftp://a.b/c file:///etc/hosts", column: 16) == nil)
        #expect(try link("https:// nothing", column: 3) == nil)
        #expect(try link("xhttps://a.b", column: 5)?.address == "https://a.b")
    }
}
