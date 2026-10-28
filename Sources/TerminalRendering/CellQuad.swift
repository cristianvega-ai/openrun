import TerminalEmulation
import simd

/// One rectangle that the renderer draws, as the shaders read it. A glyph quad
/// also names the part of a texture that it shows, and its column, which the
/// cursor needs. The fields have the layout of `Quad` in `ShaderSource`, and
/// positions are pixels of the drawable.
struct CellQuad: Equatable {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var atlasOrigin: SIMD2<Float> = .zero
    var isColor: UInt32 = 0
    var column: UInt32 = 0
    var color: SIMD4<Float>

    static func rectangle(x: Int, y: Int, width: Int, height: Int, color: TerminalColor) -> CellQuad {
        CellQuad(origin: [Float(x), Float(y)], size: [Float(width), Float(height)], color: vector(color))
    }

    static func glyph(_ entry: GlyphAtlas.Entry, column: Int, x: Int, y: Int, color: TerminalColor) -> CellQuad {
        CellQuad(
            origin: [Float(x + entry.horizontalOffset), Float(y + entry.verticalOffset)],
            size: [Float(entry.width), Float(entry.height)],
            atlasOrigin: [Float(entry.horizontalPosition), Float(entry.verticalPosition)],
            isColor: entry.isColor ? 1 : 0, column: UInt32(column),
            color: vector(color))
    }

    func moved(x: Int, y: Int) -> CellQuad {
        var quad = self
        quad.origin += [Float(x), Float(y)]
        return quad
    }

    static func vector(_ color: TerminalColor) -> SIMD4<Float> {
        SIMD4(Float(color.red) / 255, Float(color.green) / 255, Float(color.blue) / 255, 1)
    }
}
