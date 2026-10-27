import TerminalEmulation
import simd

/// One rectangle that the renderer draws, as the shaders read it. A glyph quad
/// also names the part of a texture that it shows. The fields have the layout
/// of `Quad` in `ShaderSource`, and positions are pixels of the drawable.
struct CellQuad {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var atlasOrigin: SIMD2<Float> = .zero
    var isColor: UInt32 = 0
    var unused: UInt32 = 0
    var color: SIMD4<Float>

    static func rectangle(x: Int, y: Int, width: Int, height: Int, color: TerminalColor) -> CellQuad {
        CellQuad(origin: [Float(x), Float(y)], size: [Float(width), Float(height)], color: vector(color))
    }

    static func glyph(_ entry: GlyphAtlas.Entry, x: Int, y: Int, color: TerminalColor) -> CellQuad {
        CellQuad(
            origin: [Float(x + entry.offsetX), Float(y + entry.offsetY)], size: [Float(entry.width), Float(entry.height)],
            atlasOrigin: [Float(entry.x), Float(entry.y)], isColor: entry.isColor ? 1 : 0, color: vector(color))
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
