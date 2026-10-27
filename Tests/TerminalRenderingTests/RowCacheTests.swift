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
