import Metal
import Testing
@testable import TerminalRendering

@Suite struct GlyphAtlasTests {
    private func makeAtlas(side: Int = 2048, maximumSide: Int = 8192) throws -> GlyphAtlas {
        try GlyphAtlas(device: #require(MTLCreateSystemDefaultDevice()), fonts: FontSet(pointSize: 13, scale: 2), side: side, maximumSide: maximumSide)
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
            &pixels, bytesPerRow: entry.width,
            from: MTLRegionMake2D(entry.horizontalPosition, entry.verticalPosition, entry.width, entry.height), mipmapLevel: 0)
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

    @Test func aHiddenGlyphTakesSpaceOnlyWhenItsBitmapEntersTheDrawable() throws {
        let atlas = try makeAtlas()
        let glyph = key("A")
        let bitmap = try #require(GlyphRasterizer(fonts: testFonts).bitmap(for: glyph))
        let size = (width: 80, height: 80)
        let top = -bitmap.verticalOffset
        let hidden = atlas.entry(for: glyph, at: (80 - bitmap.horizontalOffset, top), within: size)
        #expect(hidden.isEmpty && atlas.drawnCount == 0)
        let edge = atlas.entry(for: glyph, at: (79 - bitmap.horizontalOffset, top), within: size)
        #expect(!edge.isEmpty && atlas.drawnCount == 1)
    }

    @Test func aFullTextureKeepsTheEarlierGlyphs() throws {
        let atlas = try makeAtlas(side: 64)
        let first = atlas.entry(for: key("A"))
        func pixels() -> [UInt8] {
            var result = [UInt8](repeating: 0, count: first.width * first.height)
            atlas.coverage.getBytes(
                &result, bytesPerRow: first.width,
                from: MTLRegionMake2D(first.horizontalPosition, first.verticalPosition, first.width, first.height), mipmapLevel: 0)
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
                &result, bytesPerRow: first.width * 4,
                from: MTLRegionMake2D(first.horizontalPosition, first.verticalPosition, first.width, first.height), mipmapLevel: 0)
            return result
        }
        let original = pixels()
        for character in "😀😃😄😁😆😅😂🤣😊😇" { _ = atlas.entry(for: emoji(String(character))) }
        #expect(atlas.color.width > 64)
        #expect(atlas.entry(for: emoji("🙂")) == first)
        #expect(pixels() == original)
    }

    @Test func theSizeLimitDoesNotOverwriteEarlierGlyphs() throws {
        let atlas = try makeAtlas(side: 64, maximumSide: 64)
        let first = atlas.entry(for: key("A"))
        var original = [UInt8](repeating: 0, count: first.width * first.height)
        let region = MTLRegionMake2D(first.horizontalPosition, first.verticalPosition, first.width, first.height)
        atlas.coverage.getBytes(&original, bytesPerRow: first.width, from: region, mipmapLevel: 0)
        let entries = "BCDEFGHIJKLMNOPQRSTUVWXYZ".map { atlas.entry(for: key(String($0))) }
        var after = [UInt8](repeating: 0, count: original.count)
        atlas.coverage.getBytes(&after, bytesPerRow: first.width, from: region, mipmapLevel: 0)
        #expect(entries.contains { $0.isEmpty })
        #expect(atlas.coverage.width == 64)
        #expect(atlas.entry(for: key("A")) == first && after == original)
    }

    @Test func reclaimLeavesTheOldTextureForFramesInFlight() throws {
        let atlas = try makeAtlas(side: 64, maximumSide: 64)
        let first = atlas.entry(for: key("A"))
        let old = atlas.coverage
        let oldColor = atlas.color
        let region = MTLRegionMake2D(first.horizontalPosition, first.verticalPosition, first.width, first.height)
        var original = [UInt8](repeating: 0, count: first.width * first.height)
        old.getBytes(&original, bytesPerRow: first.width, from: region, mipmapLevel: 0)
        for letter in "BCDEFGHIJKLMNOPQRSTUVWXYZ" { _ = atlas.entry(for: key(String(letter))) }
        #expect(atlas.isFull && atlas.reclaim())
        #expect(!atlas.isFull && atlas.coverage !== old && atlas.color !== oldColor)
        #expect(!atlas.entry(for: key("Z")).isEmpty)
        var after = [UInt8](repeating: 0, count: original.count)
        old.getBytes(&after, bytesPerRow: first.width, from: region, mipmapLevel: 0)
        #expect(after == original)
    }
}
