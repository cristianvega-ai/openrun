import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct FrameBuilderTests {
    @Test func aQuadThatExtendsAcrossRowsBelongsToEachBand() {
        let metrics = testFonts.metrics
        let quad = CellQuad.rectangle(horizontalPosition: 0, verticalPosition: testPadding + metrics.height - 2, width: 4, height: 4, color: TerminalColor(red: 1, green: 2, blue: 3))
        #expect(FrameBuilder.bandIndices(of: quad, rowCount: 3, targetHeight: 3 * metrics.height + 2 * testPadding,
                                         metrics: metrics, padding: testPadding) == 0...1)
        let contained = CellQuad.rectangle(horizontalPosition: 0, verticalPosition: testPadding, width: 4, height: metrics.height, color: TerminalColor(red: 1, green: 2, blue: 3))
        #expect(FrameBuilder.bandIndices(of: contained, rowCount: 3, targetHeight: 3 * metrics.height + 2 * testPadding,
                                         metrics: metrics, padding: testPadding) == 0...0)
    }
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
