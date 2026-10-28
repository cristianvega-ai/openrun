import Foundation
import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct CursorShapeTests {
    private func quads(_ style: CursorStyle) -> CursorQuads {
        CursorQuads(style: style, x: 100, y: 50, width: 32, height: 31, stroke: 2, color: TerminalColor(red: 1, green: 2, blue: 3))
    }

    private func boxes(_ list: [CellQuad]) -> [[Float]] {
        list.map { [$0.origin.x, $0.origin.y, $0.size.x, $0.size.y] }
    }

    @Test func aBlockIsOneRectangleUnderTheGlyphs() {
        #expect(boxes(quads(.block).backgrounds) == [[100, 50, 32, 31]])
        #expect(quads(.block).overlays.isEmpty)
    }

    @Test func aBarAndAnUnderlineAreOneLineOnTopOfTheGlyphs() {
        #expect(boxes(quads(.bar).overlays) == [[100, 50, 4, 31]])
        #expect(boxes(quads(.underline).overlays) == [[100, 77, 32, 4]])
        #expect(quads(.bar).backgrounds.isEmpty)
    }

    @Test func aHollowBlockIsFourLines() {
        let edges = boxes(quads(.hollowBlock).overlays)
        #expect(edges == [[100, 50, 32, 2], [100, 79, 32, 2], [100, 50, 2, 31], [130, 50, 2, 31]])
    }
}

@Suite struct CursorTests {
    private let metrics = testFonts.metrics

    @Test func aBlockCursorFillsItsCellWithTheCursorColor() throws {
        let screen = try renderScreen("A\u{1B}[2 q")
        #expect(pixel(of: screen.target, column: 1, x: 0, y: 0) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, x: metrics.width - 1, y: metrics.height - 1) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 2, x: 3, y: 3) == screen.theme.background)
    }

    @Test func theTextInABlockCursorTakesTheBackgroundColor() throws {
        let screen = try renderScreen("█\u{1B}[D\u{1B}[2 q")
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.background)
    }

    @Test func aHiddenCursorDrawsNothing() throws {
        let screen = try renderScreen("A\u{1B}[?25l")
        #expect(inkCount(of: screen, columns: 1..<10, rows: 0..<3) == 0)
    }

    @Test func aBarIsALineAtTheLeftOfItsCell() throws {
        let screen = try renderScreen("A\u{1B}[6 q")
        #expect(pixel(of: screen.target, column: 1, x: 0, y: metrics.height / 2) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, x: metrics.width - 1, y: metrics.height / 2) == screen.theme.background)
    }

    @Test func anUnderlineIsALineAtTheBottomOfItsCell() throws {
        let screen = try renderScreen("A\u{1B}[4 q")
        #expect(pixel(of: screen.target, column: 1, x: metrics.width / 2, y: metrics.height - 1) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, x: metrics.width / 2, y: 0) == screen.theme.background)
    }

    @Test func aViewWithoutFocusShowsAHollowBlock() throws {
        let screen = try renderScreen("A\u{1B}[2 q", isFocused: false)
        #expect(pixel(of: screen.target, column: 1, x: 0, y: metrics.height / 2) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, x: metrics.width / 2, y: 0) == screen.theme.cursor)
        #expect(middle(of: screen.target, column: 1, row: 0) == screen.theme.background)
    }

    @Test(arguments: ["\u{1B}[1;1H", "\u{1B}[1;2H"])
    func aCursorOnAWideCharacterCoversBothOfItsCells(move: String) throws {
        let screen = try renderScreen("日\(move)\u{1B}[2 q", columns: 4)
        #expect(pixel(of: screen.target, column: 0, x: 0, y: 0) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, x: metrics.width - 1, y: 0) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 2, x: 0, y: 0) == screen.theme.background)
    }
}

@Suite struct MarkedTextTests {
    private let metrics = testFonts.metrics

    @Test func markedTextHasAnUnderlineAndTakesTheCursorsPlace() throws {
        let screen = try renderScreen("█\u{1B}[D\u{1B}[2 q", markedText: "´")
        #expect(pixel(of: screen.target, x: 3, y: metrics.underlinePosition) == screen.theme.foreground)
        #expect(pixel(of: screen.target, x: 0, y: 0) == screen.theme.background)
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.background)
    }

    @Test func markedTextThatCoversAWideCharacterHidesIt() throws {
        let screen = try renderScreen("日\u{1B}[?25l\u{1B}[1G", markedText: "a")
        #expect(inkCount(of: screen, columns: 1..<2, rows: 0..<1) < 20)
    }

    @Test func markedTextOnTheTailOfAWideCharacterHidesTheWholeGlyph() throws {
        let screen = try renderScreen("日\u{1B}[?25l\u{1B}[2G", markedText: "a")
        #expect(inkCount(of: screen, columns: 0..<1, rows: 0..<1) == 0)
        #expect(inkCount(of: screen, columns: 1..<2, rows: 0..<1) > 20)
    }

    @Test func markedTextHidesTheDecorationOfTheCellBelow() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[31;53m█\u{1B}[1G", markedText: " ")
        for x in 0..<metrics.width {
            #expect(pixel(of: screen.target, x: x, y: 0) == screen.theme.background)
        }
    }

    @Test func theMarkedCaretUsesTheWrappedTextAndTheUTF16Selection() throws {
        let atlas = try makeAtlas()
        func layout(_ location: Int) -> MarkedTextQuads.Layout {
            MarkedTextQuads.Layout(text: "🙂ab", column: 9, row: 2, columnCount: 10, rowCount: 3,
                                   selection: NSRange(location: location, length: 0), atlas: atlas)
        }
        #expect(layout(2).caret.column == 2 && layout(2).caret.row == 2)
        #expect(layout(0).caret.column == 0 && layout(0).caret.row == 2)
    }

    @Test func theCaretDoesNotSplitACombiningCharacter() throws {
        let atlas = try makeAtlas()
        func layout(_ location: Int) -> MarkedTextQuads.Layout {
            MarkedTextQuads.Layout(text: "e\u{301}日", column: 8, row: 0, columnCount: 10, rowCount: 3,
                                   selection: NSRange(location: location, length: 0), atlas: atlas)
        }
        #expect(layout(1).caret.column == 8 && layout(1).caret.row == 0)
        #expect(layout(2).caret.column == 0 && layout(2).caret.row == 1)
    }
}
