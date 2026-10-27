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
    private let queue: MTLCommandQueue
    private let atlas: GlyphAtlas
    private var cache = RowCache()
    private var background = TerminalColor(red: 0, green: 0, blue: 0)

    public init(device: MTLDevice, fonts: FontSet) throws {
        guard let queue = device.makeCommandQueue() else { throw RenderingError.commandQueueUnavailable }
        self.fonts = fonts
        self.queue = queue
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
        background = state.colors.background
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

    /// Draws the prepared rows into the target. The area around the grid and
    /// every cell without a background get the background color of the screen.
    ///
    /// - Returns: `false` when Metal could not make the commands.
    @discardableResult
    public func draw(into target: some RenderTarget) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let clear = CellQuad.vector(background)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: 1)
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.endEncoding()
        target.present(with: commands)
        commands.commit()
        return true
    }
}
