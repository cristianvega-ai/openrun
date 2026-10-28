import Metal

/// The textures that hold the glyphs of a terminal. A glyph is drawn once, and
/// then found again by its key. Text goes into a texture of coverage, and an
/// emoji, which has its own colors, goes into a second texture of colors.
final class GlyphAtlas {
    /// The place of a glyph in the texture, and the place of its bitmap in the cell.
    struct Entry: Equatable {
        let horizontalPosition, verticalPosition, width, height: Int
        let horizontalOffset, verticalOffset: Int
        let isColor: Bool
        /// An entry with no pixels draws nothing, as the glyph of a space.
        var isEmpty: Bool { width == 0 }
        static let empty = Entry(
            horizontalPosition: 0, verticalPosition: 0, width: 0, height: 0,
            horizontalOffset: 0, verticalOffset: 0, isColor: false)
    }

    private(set) var coverage: MTLTexture
    private(set) var color: MTLTexture
    /// How many times a glyph was drawn. A glyph in the texture is not drawn again.
    private(set) var drawnCount = 0
    /// A glyph could not be placed in either texture.
    private(set) var isFull = false
    private let device: MTLDevice
    private let maximumSide: Int
    private let rasterizer: GlyphRasterizer
    private var coveragePacker: AtlasPacker
    private var colorPacker: AtlasPacker
    private var entries: [GlyphKey: Entry] = [:]

    /// - Parameter side: The width of the texture of coverage in pixels. The
    ///   texture of colors has half of it, because it has 4 bytes for a pixel.
    init(device: MTLDevice, fonts: FontSet, side: Int = 2048, maximumSide: Int = 8192) throws {
        self.device = device
        self.maximumSide = maximumSide
        coverage = try Self.makeTexture(device, format: .r8Unorm, side: side)
        color = try Self.makeTexture(device, format: .bgra8Unorm, side: side / 2)
        rasterizer = GlyphRasterizer(fonts: fonts)
        coveragePacker = AtlasPacker(side: side)
        colorPacker = AtlasPacker(side: side / 2)
    }

    func columns(of text: String) -> Int {
        rasterizer.columns(of: text)
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
        while place == nil {
            guard grow(isColor: bitmap.isColor) else { isFull = true; return .empty }
            place = self.place(bitmap)
        }
        guard let place else { return .empty }
        (bitmap.isColor ? color : coverage).replace(
            region: MTLRegionMake2D(place.horizontalPosition, place.verticalPosition, bitmap.width, bitmap.height), mipmapLevel: 0,
            withBytes: bitmap.pixels, bytesPerRow: bitmap.width * (bitmap.isColor ? 4 : 1))
        return Entry(
            horizontalPosition: place.horizontalPosition, verticalPosition: place.verticalPosition,
            width: bitmap.width, height: bitmap.height,
            horizontalOffset: bitmap.horizontalOffset, verticalOffset: bitmap.verticalOffset, isColor: bitmap.isColor)
    }

    private func place(_ bitmap: GlyphRasterizer.Bitmap) -> (horizontalPosition: Int, verticalPosition: Int)? {
        bitmap.isColor
            ? colorPacker.place(width: bitmap.width, height: bitmap.height)
            : coveragePacker.place(width: bitmap.width, height: bitmap.height)
    }

    /// Replaces the textures so commands already in flight keep their pixels.
    @discardableResult
    func reclaim() -> Bool {
        guard let nextCoverage = try? Self.makeTexture(device, format: coverage.pixelFormat, side: coverage.width),
            let nextColor = try? Self.makeTexture(device, format: color.pixelFormat, side: color.width)
        else { return false }
        coverage = nextCoverage
        color = nextColor
        coveragePacker = AtlasPacker(side: coverage.width)
        colorPacker = AtlasPacker(side: color.width)
        entries.removeAll()
        isFull = false
        return true
    }

    private func grow(isColor: Bool) -> Bool {
        let old = isColor ? color : coverage
        // A bounded copy avoids a large allocation when a font has many glyphs.
        let limit = isColor ? maximumSide / 2 : maximumSide
        guard old.width < limit,
            let next = try? Self.makeTexture(device, format: old.pixelFormat, side: min(old.width * 2, limit))
        else { return false }
        let bytesPerRow = old.width * (isColor ? 4 : 1)
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * old.height)
        let region = MTLRegionMake2D(0, 0, old.width, old.height)
        old.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        next.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        if isColor {
            color = next
            colorPacker.grow(to: next.width)
        } else {
            coverage = next
            coveragePacker.grow(to: next.width)
        }
        return true
    }

    private static func makeTexture(_ device: MTLDevice, format: MTLPixelFormat, side: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: side, height: side, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderingError.textureUnavailable }
        return texture
    }
}
