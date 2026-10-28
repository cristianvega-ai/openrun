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

    @Test func aFullTextureKeepsTheEarlierGlyphs() throws {
        let atlas = try makeAtlas(side: 64)
        let first = atlas.entry(for: key("A"))
        func pixels() -> [UInt8] {
            var result = [UInt8](repeating: 0, count: first.width * first.height)
            atlas.coverage.getBytes(
                &result, bytesPerRow: first.width, from: MTLRegionMake2D(first.x, first.y, first.width, first.height), mipmapLevel: 0)
            return result
        }
        let original = pixels()
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { _ = atlas.entry(for: key(String(letter))) }
        #expect(atlas.coverage.width > 64)
        #expect(atlas.entry(for: key("A")) == first)
        #expect(pixels() == original)
        #expect(!atlas.entry(for: key("Z")).isEmpty)
    }

    @Test func aFullColorTextureKeepsTheEarlierEmoji() throws {
        let atlas = try makeAtlas(side: 128)
        func emoji(_ text: String) -> GlyphKey { GlyphKey(text: text, face: .regular, columns: 2) }
        let first = atlas.entry(for: emoji("🙂"))
        func pixels() -> [UInt8] {
            var result = [UInt8](repeating: 0, count: first.width * first.height * 4)
            atlas.color.getBytes(
                &result, bytesPerRow: first.width * 4, from: MTLRegionMake2D(first.x, first.y, first.width, first.height), mipmapLevel: 0)
            return result
        }
        let original = pixels()
        for character in "😀😃😄😁😆😅😂🤣😊😇" { _ = atlas.entry(for: emoji(String(character))) }
        #expect(atlas.color.width > 64)
        #expect(atlas.entry(for: emoji("🙂")) == first)
        #expect(pixels() == original)
    }
}
