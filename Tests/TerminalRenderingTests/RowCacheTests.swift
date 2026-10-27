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
