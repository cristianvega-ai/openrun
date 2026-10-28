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

    static func rectangle(
        horizontalPosition: Int, verticalPosition: Int, width: Int, height: Int, color: TerminalColor
    ) -> CellQuad {
        CellQuad(origin: [Float(horizontalPosition), Float(verticalPosition)],
                 size: [Float(width), Float(height)], color: vector(color))
    }

    static func glyph(
        _ entry: GlyphAtlas.Entry, column: Int, horizontalPosition: Int, verticalPosition: Int, color: TerminalColor
    ) -> CellQuad {
        CellQuad(
            origin: [Float(horizontalPosition + entry.horizontalOffset), Float(verticalPosition + entry.verticalOffset)],
            size: [Float(entry.width), Float(entry.height)],
            atlasOrigin: [Float(entry.horizontalPosition), Float(entry.verticalPosition)],
            isColor: entry.isColor ? 1 : 0, column: UInt32(column),
            color: vector(color))
    }

    func moved(horizontalOffset: Int, verticalOffset: Int) -> CellQuad {
        var quad = self
        quad.origin += [Float(horizontalOffset), Float(verticalOffset)]
        return quad
    }

    static func vector(_ color: TerminalColor) -> SIMD4<Float> {
        SIMD4(Float(color.red) / 255, Float(color.green) / 255, Float(color.blue) / 255, 1)
    }
}
