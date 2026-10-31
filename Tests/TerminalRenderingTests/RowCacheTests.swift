import Metal
import Testing
import TerminalEmulation
import TerminalTheme
@testable import TerminalRendering

@Suite struct RowQuadrilateralsTests {
    @Test func eachVisibleCharacterMakesOneGlyphQuadrilateralAndASpaceNone() throws {
        let screen = try makeScreen("Hi there")
        let rows = try quadrilaterals(of: screen.state, atlas: makeAtlas())
        #expect(rows[0].glyphs.count == 7)
        #expect(rows[0].backgrounds.isEmpty)
        #expect(rows[1].glyphs.isEmpty)
    }

    @Test func glyphQuadrilateralsKnowTheirColumnsAndWideCharactersAreListed() throws {
        let screen = try makeScreen("a日 b", columns: 8)
        let row = try quadrilaterals(of: screen.state, atlas: makeAtlas())[0]
        #expect(row.glyphs.map(\.column) == [0, 1, 4])
        #expect(row.wideColumns == [1])
    }

    @Test func aBackgroundThatDiffersFromTheDefaultMakesARectangleForEachCell() throws {
        let screen = try makeScreen("\u{1B}[44m  ")
        let row = try quadrilaterals(of: screen.state, atlas: makeAtlas())[0]
        let blue = screen.state.colors.palette[4]
        #expect(row.backgrounds.map(\.origin.x) == [0, Float(testFonts.cellWidth)])
        #expect(row.backgrounds.allSatisfy { $0.color == CellQuadrilateral.vector(blue) })
    }

    @Test func aWideCharacterMakesOneGlyphQuadrilateralAndAnEmojiAColorQuadrilateral() throws {
        let screen = try makeScreen("日🙂", columns: 6)
        let glyphs = try quadrilaterals(of: screen.state, atlas: makeAtlas())[0].glyphs
        #expect(glyphs.map(\.isColor) == [0, 1])
    }

    @Test(arguments: [TerminalColorScheme.dark, .light])
    func selectionKeepsInverseTextLegibleAndPreservesOtherColors(scheme: TerminalColorScheme) throws {
        let theme = TerminalTheme.graphite(for: scheme)
        let background = theme.background, selection = theme.selection
        let output = "\u{1B}[7;4mA\u{1B}[48;2;\(background.red);\(background.green);\(background.blue)mB"
            + "\u{1B}[48;2;\(selection.red);\(selection.green);\(selection.blue)mC"
            + "\u{1B}[42;58;5;1mD\u{1B}[0;32mE \u{1B}[0;7mF\u{1B}[7;42;31mG"
        let screen = try makeScreen(output)
        try theme.apply(to: screen.terminal)
        try screen.terminal.selectWord(at: ViewportCell(column: 0, row: 0))
        try screen.state.update(from: screen.terminal)
        var row: RowQuadrilaterals?
        let atlas = try makeAtlas()
        try screen.state.forEachRow(onlyChanged: false) {
            if row == nil {
                row = try RowQuadrilaterals(row: $0, colors: screen.state.colors, selection: selection,
                                            atlas: atlas, metrics: testFonts.metrics)
            }
        }
        let result = try #require(row)
        let foreground = CellQuadrilateral.vector(theme.foreground), green = CellQuadrilateral.vector(theme.firstSixteenColors[2])
        #expect(result.glyphs.map(\.color) == [foreground, foreground, foreground, green, green,
                                                CellQuadrilateral.vector(background), green])
        #expect(result.decorations.map(\.color) == [foreground, foreground, foreground,
                                                     CellQuadrilateral.vector(theme.firstSixteenColors[1])])
        #expect(result.backgrounds.map(\.color) == Array(repeating: CellQuadrilateral.vector(selection), count: 5)
                + [foreground, CellQuadrilateral.vector(theme.firstSixteenColors[1])])
    }
}

@Suite struct RowCacheTests {
    private func firstUpdate(rows: UInt16 = 5) throws -> (terminal: Terminal, state: RenderState, atlas: GlyphAtlas, cache: RowCache) {
        let screen = try makeScreen("a\r\nb", rows: rows)
        let atlas = try makeAtlas()
        var cache = RowCache()
        #expect(try update(&cache, from: screen.state, atlas: atlas).rowsPrepared == Int(rows))
        screen.state.markClean()
        return (screen.terminal, screen.state, atlas, cache)
    }

    @Test func aChangeInOneRowPreparesOneRow() throws {
        var (terminal, state, atlas, cache) = try firstUpdate()
        terminal.write("x")
        try state.update(from: terminal)
        let statistics = try update(&cache, from: state, atlas: atlas)
        #expect(statistics == FrameStatistics(rowsPrepared: 1, rowsReused: 4))
    }

    @Test func noChangePreparesNoRow() throws {
        var (terminal, state, atlas, cache) = try firstUpdate()
        try state.update(from: terminal)
        #expect(try update(&cache, from: state, atlas: atlas).rowsPrepared == 0)
    }

    @Test func aNewGridSizeOrNewColorsPrepareEveryRow() throws {
        var (terminal, state, atlas, cache) = try firstUpdate()
        try terminal.resize(to: TerminalSize(columns: 30, rows: 5))
        try state.update(from: terminal)
        #expect(try update(&cache, from: state, atlas: atlas).rowsPrepared == 5)
        state.markClean()
        try terminal.setDefaultBackgroundColor(TerminalColor(red: 1, green: 2, blue: 3))
        try state.update(from: terminal)
        #expect(try update(&cache, from: state, atlas: atlas).rowsPrepared == 5)
    }
}

@Suite struct RendererPrepareTests {
    @Test func aChangeInOneRowReadsOneRow() throws {
        let screen = try makeScreen("a\r\nb", rows: 5)
        let renderer = try TerminalRenderer(device: #require(MTLCreateSystemDefaultDevice()), fonts: testFonts, selectionColor: selectionColor)
        #expect(try renderer.prepare(from: screen.state).rowsPrepared == 5)
        screen.state.markClean()
        screen.terminal.write("x")
        try screen.state.update(from: screen.terminal)
        #expect(try renderer.prepare(from: screen.state) == FrameStatistics(rowsPrepared: 1, rowsReused: 4))
    }

    @Test func aNewSelectionColorReadsEveryRow() throws {
        let screen = try makeScreen("a\r\nb", rows: 5)
        let renderer = try TerminalRenderer(device: #require(MTLCreateSystemDefaultDevice()), fonts: testFonts, selectionColor: selectionColor)
        try renderer.prepare(from: screen.state)
        screen.state.markClean()
        renderer.selectionColor = TerminalColor(red: 9, green: 9, blue: 9)
        #expect(try renderer.prepare(from: screen.state).rowsPrepared == 5)
    }

    @Test func aGridAndItsPaddingMakeThePixelSize() throws {
        let renderer = try TerminalRenderer(device: #require(MTLCreateSystemDefaultDevice()), fonts: testFonts, selectionColor: selectionColor)
        let size = renderer.pixelSize(for: TerminalSize(columns: 10, rows: 3))
        #expect(size.width == 2 * 16 + 10 * testFonts.cellWidth)
        #expect(size.height == 2 * 16 + 3 * testFonts.cellHeight)
    }
}

@Suite struct MarkedTextQuadrilateralsTests {
    private func quadrilaterals(_ text: String, column: Int = 2, columnCount: Int = 10) throws -> MarkedTextQuadrilaterals {
        let colors = try makeScreen("").state.colors
        return try MarkedTextQuadrilaterals(
            text: text, column: column, row: 1, columnCount: columnCount, rowCount: 3, colors: colors, atlas: makeAtlas(),
            metrics: testFonts.metrics, padding: testPadding)
    }

    @Test func eachCharacterHasABackgroundAndAnUnderlineAndWideCharactersTakeTwoCells() throws {
        let marked = try quadrilaterals("a日é")
        #expect(marked.coveredColumns == [1: 2..<6])
        #expect(marked.backgrounds.map(\.size.x) == [16, 32, 16])
        #expect(marked.overlays.count == 4)
        #expect(marked.glyphs.map(\.column) == [2, 3, 5])
        #expect(marked.backgrounds[0].origin.y == Float(testPadding + testFonts.cellHeight))
    }

    @Test func theTextContinuesAtTheLeftOfTheNextRow() throws {
        #expect(try quadrilaterals("abcdef", column: 8).coveredColumns == [1: 8..<10, 2: 0..<4])
        #expect(try quadrilaterals("日", column: 9).coveredColumns == [2: 0..<2])
    }
}
