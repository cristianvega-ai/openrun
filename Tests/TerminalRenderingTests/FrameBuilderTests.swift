import Testing
@testable import TerminalRendering

@Suite struct FrameBuilderTests {
    @Test func rowsMoveDownByTheirIndexAndInByThePadding() throws {
        let screen = try makeScreen("\u{1B}[44m \u{1B}[0m\r\n\u{1B}[44m ", rows: 2)
        let atlas = try makeAtlas()
        var cache = RowCache()
        _ = try update(&cache, from: screen.state, atlas: atlas)
        let frame = FrameBuilder(cache: cache, metrics: testFonts.metrics, padding: 16)
        #expect(frame.backgrounds.map(\.origin) == [[16, 16], [16, 16 + Float(testFonts.cellHeight)]])
        #expect(frame.glyphs.isEmpty)
    }

    @Test func theCellLayoutMatchesTheShader() {
        #expect(MemoryLayout<CellQuad>.stride == 48)
        #expect(MemoryLayout<CellQuad>.offset(of: \.atlasOrigin) == 16)
        #expect(MemoryLayout<CellQuad>.offset(of: \.color) == 32)
    }
}
