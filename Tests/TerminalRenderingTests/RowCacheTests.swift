import Metal
import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct RowQuadsTests {
    @Test func eachVisibleCharacterMakesOneGlyphQuadAndASpaceNone() throws {
        let screen = try makeScreen("Hi there")
        let rows = try quads(of: screen.state, atlas: makeAtlas())
        #expect(rows[0].glyphs.count == 7)
        #expect(rows[0].backgrounds.isEmpty)
        #expect(rows[1].glyphs.isEmpty)
    }

    @Test func glyphQuadsKnowTheirColumnsAndWideCharactersAreListed() throws {
        let screen = try makeScreen("a日 b", columns: 8)
        let row = try quads(of: screen.state, atlas: makeAtlas())[0]
        #expect(row.glyphs.map(\.column) == [0, 1, 4])
        #expect(row.wideColumns == [1])
    }

    @Test func aBackgroundThatDiffersFromTheDefaultMakesARectangleForEachCell() throws {
        let screen = try makeScreen("\u{1B}[44m  ")
        let row = try quads(of: screen.state, atlas: makeAtlas())[0]
        let blue = screen.state.colors.palette[4]
        #expect(row.backgrounds.map(\.origin.x) == [0, Float(testFonts.cellWidth)])
        #expect(row.backgrounds.allSatisfy { $0.color == CellQuad.vector(blue) })
    }

    @Test func aWideCharacterMakesOneGlyphQuadAndAnEmojiAColorQuad() throws {
        let screen = try makeScreen("日🙂", columns: 6)
        let glyphs = try quads(of: screen.state, atlas: makeAtlas())[0].glyphs
        #expect(glyphs.map(\.isColor) == [0, 1])
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

@Suite struct MarkedTextQuadsTests {
    private func quads(_ text: String, column: Int = 2, columnCount: Int = 10) throws -> MarkedTextQuads {
        let colors = try makeScreen("").state.colors
        return try MarkedTextQuads(
            text: text, column: column, row: 1, columnCount: columnCount, rowCount: 3, colors: colors, atlas: makeAtlas(),
            metrics: testFonts.metrics, padding: testPadding)
    }

    @Test func eachCharacterHasABackgroundAndAnUnderlineAndWideCharactersTakeTwoCells() throws {
        let marked = try quads("a日é")
        #expect(marked.coveredColumns == [1: 2..<6])
        #expect(marked.backgrounds.map(\.size.x) == [16, 32, 16])
        #expect(marked.overlays.count == 4)
        #expect(marked.glyphs.map(\.column) == [2, 3, 5])
        #expect(marked.backgrounds[0].origin.y == Float(testPadding + testFonts.cellHeight))
    }

    @Test func theTextContinuesAtTheLeftOfTheNextRow() throws {
        #expect(try quads("abcdef", column: 8).coveredColumns == [1: 8..<10, 2: 0..<4])
        #expect(try quads("日", column: 9).coveredColumns == [2: 0..<2])
    }
}
