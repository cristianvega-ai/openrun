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
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let shaders: ShaderLibrary
    private let atlas: GlyphAtlas
    private var cache = RowCache()
    private var background = TerminalColor(red: 0, green: 0, blue: 0)
    // The graphics processor reads one buffer while the processor fills the next.
    private var buffers: [MTLBuffer?] = [nil, nil, nil]
    private var bufferIndex = 0
    private let framesInFlight = DispatchSemaphore(value: 3)

    public init(device: MTLDevice, fonts: FontSet, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        guard let queue = device.makeCommandQueue() else { throw RenderingError.commandQueueUnavailable }
        self.device = device
        self.fonts = fonts
        self.queue = queue
        shaders = try ShaderLibrary(device: device, pixelFormat: pixelFormat)
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

    /// Draws the prepared rows into the target. The space around the grid and
    /// every cell without a background color get the background of the screen.
    ///
    /// - Returns: `false` when the graphics processor is 3 frames behind, or
    ///   when Metal could not make the commands. The caller tries again at the
    ///   next frame.
    @discardableResult
    public func draw(into target: some RenderTarget) -> Bool {
        guard framesInFlight.wait(timeout: .now()) == .success else { return false }
        guard encode(into: target) else {
            framesInFlight.signal()
            return false
        }
        return true
    }

    private func encode(into target: some RenderTarget) -> Bool {
        let frame = FrameBuilder(cache: cache, metrics: fonts.metrics, padding: padding)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let clear = CellQuad.vector(background)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: 1)
        guard let (buffer, offsets) = copy([frame.backgrounds, frame.glyphs]), let commands = queue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return false }
        var viewport = SIMD2<Float>(Float(target.texture.width), Float(target.texture.height))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        draw(frame.backgrounds, with: shaders.rectangles, buffer: buffer, offset: offsets[0], encoder: encoder)
        encoder.setFragmentTexture(atlas.coverage, index: 0)
        encoder.setFragmentTexture(atlas.color, index: 1)
        draw(frame.glyphs, with: shaders.glyphs, buffer: buffer, offset: offsets[1], encoder: encoder)
        encoder.endEncoding()
        let finished = framesInFlight
        commands.addCompletedHandler { _ in finished.signal() }
        target.present(with: commands)
        commands.commit()
        return true
    }

    private func draw(
        _ quads: [CellQuad], with pipeline: MTLRenderPipelineState, buffer: MTLBuffer, offset: Int, encoder: MTLRenderCommandEncoder
    ) {
        guard !quads.isEmpty else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: offset, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: quads.count)
    }

    /// Copies the lists of quads into the next buffer, and gives the buffer
    /// and the offset of each list.
    private func copy(_ lists: [[CellQuad]]) -> (MTLBuffer, [Int])? {
        // The graphics processor reads each list from an offset of 256 bytes.
        let sizes = lists.map { ($0.count * MemoryLayout<CellQuad>.stride + 255) / 256 * 256 }
        let offsets = sizes.indices.map { sizes[..<$0].reduce(0, +) }
        let needed = sizes.reduce(0, +)
        let slot = bufferIndex
        bufferIndex = (bufferIndex + 1) % buffers.count
        if (buffers[slot]?.length ?? -1) < needed {
            buffers[slot] = device.makeBuffer(length: max(needed + needed / 2, 1 << 16), options: .storageModeShared)
        }
        guard let buffer = buffers[slot] else { return nil }
        for (list, offset) in zip(lists, offsets) where !list.isEmpty {
            list.withUnsafeBytes { buffer.contents().advanced(by: offset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
        return (buffer, offsets)
    }
}
