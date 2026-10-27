import Metal

/// The textures that hold the glyphs of a terminal. A glyph is drawn once, and
/// then found again by its key. Text goes into a texture of coverage, and an
/// emoji, which has its own colors, goes into a second texture of colors.
final class GlyphAtlas {
    /// The place of a glyph in the texture, and the place of its bitmap in the cell.
    struct Entry: Equatable {
        let x, y, width, height, offsetX, offsetY: Int
        let isColor: Bool
        /// An entry with no pixels draws nothing, as the glyph of a space.
        var isEmpty: Bool { width == 0 }
        static let empty = Entry(x: 0, y: 0, width: 0, height: 0, offsetX: 0, offsetY: 0, isColor: false)
    }

    let coverage: MTLTexture
    let color: MTLTexture
    /// How many times a glyph was drawn. A glyph in the texture is not drawn again.
    private(set) var drawnCount = 0
    /// Changes when a full texture starts again. The earlier entries are then
    /// wrong, and whoever kept one must ask again.
    private(set) var generation = 0
    private let rasterizer: GlyphRasterizer
    private var coveragePacker: AtlasPacker
    private var colorPacker: AtlasPacker
    private var entries: [GlyphKey: Entry] = [:]

    /// - Parameter side: The width of the texture of coverage in pixels. The
    ///   texture of colors has half of it, because it has 4 bytes for a pixel.
    init(device: MTLDevice, fonts: FontSet, side: Int = 2048) throws {
        coverage = try Self.makeTexture(device, format: .r8Unorm, side: side)
        color = try Self.makeTexture(device, format: .bgra8Unorm, side: side / 2)
        rasterizer = GlyphRasterizer(fonts: fonts)
        coveragePacker = AtlasPacker(side: side)
        colorPacker = AtlasPacker(side: side / 2)
    }

    func entry(for key: GlyphKey) -> Entry {
        if let entry = entries[key] { return entry }
        let entry = rasterizer.bitmap(for: key).map(store) ?? .empty
        entries[key] = entry
        return entry
    }

    private func store(_ bitmap: GlyphRasterizer.Bitmap) -> Entry {
        drawnCount += 1
        var place = place(bitmap)
        if place == nil {
            // A full texture is rare. Starting again is simpler than a choice of glyphs to drop.
            coveragePacker.reset()
            colorPacker.reset()
            entries.removeAll()
            generation += 1
            place = self.place(bitmap)
        }
        guard let place else { return .empty }
        (bitmap.isColor ? color : coverage).replace(
            region: MTLRegionMake2D(place.x, place.y, bitmap.width, bitmap.height), mipmapLevel: 0,
            withBytes: bitmap.pixels, bytesPerRow: bitmap.width * (bitmap.isColor ? 4 : 1))
        return Entry(
            x: place.x, y: place.y, width: bitmap.width, height: bitmap.height,
            offsetX: bitmap.offsetX, offsetY: bitmap.offsetY, isColor: bitmap.isColor)
    }

    private func place(_ bitmap: GlyphRasterizer.Bitmap) -> (x: Int, y: Int)? {
        bitmap.isColor
            ? colorPacker.place(width: bitmap.width, height: bitmap.height)
            : coveragePacker.place(width: bitmap.width, height: bitmap.height)
    }

    private static func makeTexture(_ device: MTLDevice, format: MTLPixelFormat, side: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: side, height: side, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderingError.textureUnavailable }
        return texture
    }
}
