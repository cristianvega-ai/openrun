import Metal

/// The texture that holds the glyphs of a terminal. A glyph is drawn once,
/// and then found again by its key.
final class GlyphAtlas {
    /// The place of a glyph in the texture, and the place of its bitmap in the cell.
    struct Entry: Equatable {
        let x, y, width, height, offsetX, offsetY: Int
        /// An entry with no pixels draws nothing, as the glyph of a space.
        var isEmpty: Bool { width == 0 }
        static let empty = Entry(x: 0, y: 0, width: 0, height: 0, offsetX: 0, offsetY: 0)
    }

    let coverage: MTLTexture
    /// How many times a glyph was drawn. A glyph in the texture is not drawn again.
    private(set) var drawnCount = 0
    /// Changes when a full texture starts again. The earlier entries are then
    /// wrong, and whoever kept one must ask again.
    private(set) var generation = 0
    private let rasterizer: GlyphRasterizer
    private var packer: AtlasPacker
    private var entries: [GlyphKey: Entry] = [:]

    init(device: MTLDevice, fonts: FontSet, side: Int = 2048) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderingError.textureUnavailable }
        coverage = texture
        rasterizer = GlyphRasterizer(fonts: fonts)
        packer = AtlasPacker(side: side)
    }

    func entry(for key: GlyphKey) -> Entry {
        if let entry = entries[key] { return entry }
        let entry = rasterizer.bitmap(for: key).map(store) ?? .empty
        entries[key] = entry
        return entry
    }

    private func store(_ bitmap: GlyphRasterizer.Bitmap) -> Entry {
        drawnCount += 1
        var place = packer.place(width: bitmap.width, height: bitmap.height)
        if place == nil {
            // A full texture is rare. Starting again is simpler than a choice of glyphs to drop.
            packer.reset()
            entries.removeAll()
            generation += 1
            place = packer.place(width: bitmap.width, height: bitmap.height)
        }
        guard let place else { return .empty }
        coverage.replace(
            region: MTLRegionMake2D(place.x, place.y, bitmap.width, bitmap.height), mipmapLevel: 0,
            withBytes: bitmap.pixels, bytesPerRow: bitmap.width)
        return Entry(
            x: place.x, y: place.y, width: bitmap.width, height: bitmap.height,
            offsetX: bitmap.offsetX, offsetY: bitmap.offsetY)
    }
}
