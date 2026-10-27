import Metal
import TerminalEmulation

/// Draws the screen of a terminal with Metal.
///
/// `prepare(from:)` reads the rows that changed and keeps the quads of the
/// others. A frame that follows holds all quads, because the work of the
/// graphics processor is small. The saving is in the reading of the rows.
public final class TerminalRenderer {
    public let fonts: FontSet
    /// The space around the grid in pixels: 8 points.
    public let padding: Int
    private let atlas: GlyphAtlas
    private var cache = RowCache()

    public init(device: MTLDevice, fonts: FontSet) throws {
        self.fonts = fonts
        padding = Int((8 * fonts.scale).rounded())
        atlas = try GlyphAtlas(device: device, fonts: fonts)
    }

    /// The size of a target that holds a grid and the space around it.
    public func pixelSize(for grid: TerminalSize) -> (width: Int, height: Int) {
        (2 * padding + Int(grid.columns) * fonts.cellWidth, 2 * padding + Int(grid.rows) * fonts.cellHeight)
    }

    /// Makes new quads for the rows that changed since the last call. Call it
    /// after `RenderState.update`, and `markClean` when the frame is drawn.
    @discardableResult
    public func prepare(from state: RenderState) throws -> FrameStatistics {
        func update() throws -> FrameStatistics {
            try cache.update(from: state, atlasGeneration: atlas.generation) {
                try RowQuads(row: $0, colors: state.colors, atlas: atlas, metrics: fonts.metrics)
            }
        }
        let generation = atlas.generation
        let statistics = try update()
        // A full atlas starts again, and the rows that were made before that
        // point to glyphs that are gone. Another update makes them all again.
        return atlas.generation == generation ? statistics : try update()
    }
}
