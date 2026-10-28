import Foundation
import Metal
import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct CursorShapeTests {
    private func quads(_ style: CursorStyle) -> CursorQuads {
        CursorQuads(style: style, horizontalPosition: 100, verticalPosition: 50, width: 32, height: 31, stroke: 2, color: TerminalColor(red: 1, green: 2, blue: 3))
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
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: 0, verticalPosition: 0) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: metrics.width - 1, verticalPosition: metrics.height - 1) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 2, horizontalPosition: 3, verticalPosition: 3) == screen.theme.background)
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
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: 0, verticalPosition: metrics.height / 2) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: metrics.width - 1, verticalPosition: metrics.height / 2) == screen.theme.background)
    }

    @Test func anUnderlineIsALineAtTheBottomOfItsCell() throws {
        let screen = try renderScreen("A\u{1B}[4 q")
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: metrics.width / 2, verticalPosition: metrics.height - 1) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: metrics.width / 2, verticalPosition: 0) == screen.theme.background)
    }

    @Test func aViewWithoutFocusShowsAHollowBlock() throws {
        let screen = try renderScreen("A\u{1B}[2 q", isFocused: false)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: 0, verticalPosition: metrics.height / 2) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: metrics.width / 2, verticalPosition: 0) == screen.theme.cursor)
        #expect(middle(of: screen.target, column: 1, row: 0) == screen.theme.background)
    }

    @Test(arguments: ["\u{1B}[1;1H", "\u{1B}[1;2H"])
    func aCursorOnAWideCharacterCoversBothOfItsCells(move: String) throws {
        let screen = try renderScreen("日\(move)\u{1B}[2 q", columns: 4)
        #expect(pixel(of: screen.target, column: 0, horizontalPosition: 0, verticalPosition: 0) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: metrics.width - 1, verticalPosition: 0) == screen.theme.cursor)
        #expect(pixel(of: screen.target, column: 2, horizontalPosition: 0, verticalPosition: 0) == screen.theme.background)
    }
}

@Suite struct MarkedTextTests {
    private let metrics = testFonts.metrics

    @Test func markedTextHasAnUnderlineAndTakesTheCursorsPlace() throws {
        let screen = try renderScreen("█\u{1B}[D\u{1B}[2 q", markedText: "´")
        #expect(pixel(of: screen.target, horizontalPosition: 3, verticalPosition: metrics.underlinePosition) == screen.theme.foreground)
        #expect(pixel(of: screen.target, horizontalPosition: 0, verticalPosition: 0) == screen.theme.background)
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.background)
    }

    @Test func markedTextShowsTheCaretAfterItsLastCharacter() throws {
        let screen = try renderScreen("\u{1B}[?25l", markedText: "a")
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: 0, verticalPosition: metrics.height / 2) == screen.theme.cursor)
    }

    @Test func theSelectedSixteenBitCodeUnitRangeHasTheSelectionColor() throws {
        let screen = try renderScreen("\u{1B}[?25l", markedText: "A🙂B", markedTextSelection: NSRange(location: 1, length: 2))
        #expect(pixel(of: screen.target, column: 0, horizontalPosition: 0, verticalPosition: 0) == screen.theme.background)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: 0, verticalPosition: 0) == screen.theme.selection)
        #expect(pixel(of: screen.target, column: 2, horizontalPosition: 0, verticalPosition: 0) == screen.theme.selection)
        #expect(pixel(of: screen.target, column: 3, horizontalPosition: 0, verticalPosition: 0) == screen.theme.background)
    }

    @Test func candidatePositionsUseTheDisplayedLayoutAndSixteenBitCodeUnitBoundaries() throws {
        let renderer = try TerminalRenderer(device: #require(MTLCreateSystemDefaultDevice()), fonts: testFonts, selectionColor: selectionColor)
        let size = TerminalSize(columns: 10, rows: 3)
        let position = ViewportCell(column: 9, row: 2)
        renderer.markedText = "🙂ab"
        renderer.markedTextSelection = NSRange(location: 2, length: 0)
        #expect(renderer.markedTextCaretPosition(at: position, in: size) == ViewportCell(column: 2, row: 2))
        #expect(renderer.markedTextCaretPosition(at: position, in: size, for: NSRange(location: 1, length: 0)) == ViewportCell(column: 0, row: 2))
        #expect(renderer.markedTextCaretPosition(at: position, in: size, for: NSRange(location: 3, length: 0)) == ViewportCell(column: 3, row: 2))
        #expect(renderer.markedTextSelection == NSRange(location: 2, length: 0))
        renderer.markedText = "a"
        renderer.markedTextSelection = nil
        #expect(renderer.markedTextCaretPosition(at: ViewportCell(column: 9, row: 1), in: size) == ViewportCell(column: 10, row: 1))
        renderer.markedText = String(repeating: "a", count: 50)
        renderer.markedTextSelection = NSRange(location: 0, length: 0)
        #expect(renderer.markedTextCaretPosition(at: position, in: size, for: NSRange(location: 49, length: 0)) == nil)
    }

    @Test func markedTextThatCoversAWideCharacterHidesIt() throws {
        let screen = try renderScreen("日\u{1B}[?25l\u{1B}[1G", markedText: "a", markedTextSelection: NSRange(location: 0, length: 0))
        #expect(inkCount(of: screen, columns: 1..<2, rows: 0..<1) < 20)
    }

    @Test func markedTextOnTheTailOfAWideCharacterHidesTheWholeGlyph() throws {
        let screen = try renderScreen("日\u{1B}[?25l\u{1B}[2G", markedText: "a")
        #expect(inkCount(of: screen, columns: 0..<1, rows: 0..<1) == 0)
        #expect(inkCount(of: screen, columns: 1..<2, rows: 0..<1) > 20)
    }

    @Test func markedTextHidesTheDecorationOfTheCellBelow() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[31;53m█\u{1B}[1G", markedText: " ")
        for horizontalPosition in 0..<metrics.width {
            #expect(pixel(of: screen.target, horizontalPosition: horizontalPosition, verticalPosition: 0) == screen.theme.background)
        }
    }

    @Test func aWideMarkedCharacterWrapsAtTheLastColumn() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[3;10H", columns: 10, rows: 3, markedText: "日")
        #expect(inkCount(of: screen, columns: 0..<2, rows: 2..<3) > 100)
        if let folder = ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] {
            try screen.target.saveImage(to: URL(fileURLWithPath: "\(folder)/marked-wide-edge.png"))
        }
    }

    @Test func aLongMarkedTextWrapsAndStaysInTheGrid() throws {
        let single = try renderScreen("\u{1B}[?25l\u{1B}[3;10H", columns: 10, rows: 3, markedText: "a")
        #expect(inkCount(of: single, columns: 9..<10, rows: 2..<3) > 20)
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[3;10H", columns: 10, rows: 3, markedText: "abc")
        #expect(inkCount(of: screen, columns: 9..<10, rows: 1..<2) > 20)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 2..<3) > 40)
        if let folder = ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] {
            try screen.target.saveImage(to: URL(fileURLWithPath: "\(folder)/marked-long-edge.png"))
        }
    }

    @Test func theMarkedCaretUsesTheWrappedTextAndTheSixteenBitCodeUnitSelection() throws {
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
