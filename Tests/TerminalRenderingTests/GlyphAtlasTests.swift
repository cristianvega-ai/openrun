import Metal
import Testing
@testable import TerminalRendering

@Suite struct GlyphAtlasTests {
    private func makeAtlas(side: Int = 2048) throws -> GlyphAtlas {
        try GlyphAtlas(device: #require(MTLCreateSystemDefaultDevice()), fonts: FontSet(pointSize: 13, scale: 2), side: side)
    }

    private func key(_ text: String) -> GlyphKey {
        GlyphKey(text: text, face: .regular, columns: 1)
    }

    @Test func aGlyphIsDrawnOnceAndItsPixelsAreInTheTexture() throws {
        let atlas = try makeAtlas()
        let entry = atlas.entry(for: key("A"))
        #expect(atlas.entry(for: key("A")) == entry)
        #expect(atlas.drawnCount == 1)
        var pixels = [UInt8](repeating: 0, count: entry.width * entry.height)
        atlas.coverage.getBytes(
            &pixels, bytesPerRow: entry.width, from: MTLRegionMake2D(entry.x, entry.y, entry.width, entry.height), mipmapLevel: 0)
        #expect(pixels.contains { $0 > 200 })
    }

    @Test func anEmojiGoesIntoTheTextureOfColors() throws {
        let atlas = try makeAtlas()
        let emoji = atlas.entry(for: GlyphKey(text: "🙂", face: .regular, columns: 2))
        #expect(emoji.isColor && !emoji.isEmpty)
        #expect(!atlas.entry(for: key("A")).isColor)
    }

    @Test func aSpaceHasAnEmptyEntry() throws {
        let atlas = try makeAtlas()
        #expect(atlas.entry(for: key(" ")).isEmpty)
        #expect(atlas.drawnCount == 0)
    }

    @Test func aFullTextureStartsAgain() throws {
        let atlas = try makeAtlas(side: 64)
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { _ = atlas.entry(for: key(String(letter))) }
        #expect(atlas.generation > 0)
        #expect(!atlas.entry(for: key("Z")).isEmpty)
    }
}
