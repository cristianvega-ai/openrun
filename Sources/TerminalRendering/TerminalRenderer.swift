import Foundation
import Metal
import TerminalEmulation

/// Draws the screen of a terminal with Metal.
///
/// `prepare(from:)` keeps the quads of unchanged rows. Drawing updates the
/// changed bands of a retained texture before it presents the whole picture.
public final class TerminalRenderer {
    public let fonts: FontSet
    /// The space around the grid in pixels: 8 points.
    public let padding: Int
    /// The background of the selected cells. A new color changes every row.
    public var selectionColor: TerminalColor {
        didSet { if selectionColor != oldValue { cache.forget() } }
    }
    /// The text of an input method, before the user ends it. The renderer draws it
    /// at the cursor with an underline, and it is not in the terminal.
    public var markedText: String?
    /// The UTF-16 range selected in marked text, or `nil` for its end.
    public var markedTextSelection: NSRange?
    /// Whether the view has the keyboard focus. Without it, the cursor is a hollow block.
    public var isFocused = true
    /// Whether the cursor is in the shown phase of its blink. Without it, the renderer draws no cursor.
    public var isCursorShown = true
    /// Whether the picture has the flash of the visual bell over it.
    public var isFlashing = false
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let shaders: ShaderLibrary
    private let atlas: GlyphAtlas
    private var cache = RowCache()
    private var colors: RenderColors?
    private var cursor: RenderCursor?
    private var columnCount = 0
    private var rowCount = 0
    private var backing: MTLTexture?
    private var grid: TerminalSize?
    private var drawnGrid: TerminalSize?
    private var drawnColors: RenderColors?
    private var drawnSelectionColor: TerminalColor?
    private var drawnBands: [FrameBuilder.Band]?
    private var reclaimedForFrame = false
    private(set) var rowsDrawn = 0
    // The graphics processor reads one buffer while the processor fills the next.
    private var buffers: [MTLBuffer?] = [nil, nil, nil]
    private var bufferIndex = 0
    private let framesInFlight = DispatchSemaphore(value: 3)

    public convenience init(device: MTLDevice, fonts: FontSet, selectionColor: TerminalColor, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        try self.init(device: device, fonts: fonts, selectionColor: selectionColor, pixelFormat: pixelFormat, atlasSide: 2048)
    }

    init(device: MTLDevice, fonts: FontSet, selectionColor: TerminalColor, pixelFormat: MTLPixelFormat = .bgra8Unorm,
         atlasSide: Int, atlasMaximumSide: Int = 8192) throws {
        guard let queue = device.makeCommandQueue() else { throw RenderingError.commandQueueUnavailable }
        self.device = device
        self.fonts = fonts
        self.selectionColor = selectionColor
        self.queue = queue
        shaders = try ShaderLibrary(device: device, pixelFormat: pixelFormat)
        padding = Int((8 * fonts.scale).rounded())
        atlas = try GlyphAtlas(device: device, fonts: fonts, side: atlasSide, maximumSide: atlasMaximumSide)
    }

    /// The size of a target that holds a grid and the space around it.
    public func pixelSize(for grid: TerminalSize) -> (width: Int, height: Int) {
        (2 * padding + Int(grid.columns) * fonts.cellWidth, 2 * padding + Int(grid.rows) * fonts.cellHeight)
    }

    /// The position of a UTF-16 range in the displayed marked text.
    /// The end of a row can have a column equal to the grid width.
    /// Returns `nil` when there is no marked text or the range is outside the grid.
    public func markedTextCaretPosition(at position: ViewportCell, in size: TerminalSize, for range: NSRange? = nil) -> ViewportCell? {
        guard let markedText, !markedText.isEmpty, size.columns > 0, size.rows > 0 else { return nil }
        let layout = MarkedTextQuads.Layout(
            text: markedText, column: min(Int(position.column), Int(size.columns) - 1),
            row: min(Int(position.row), Int(size.rows) - 1), columnCount: Int(size.columns), rowCount: Int(size.rows),
            selection: markedTextSelection, atlas: atlas)
        let caret: (column: Int, row: Int)
        if let range, range.location != NSNotFound {
            let location = min(max(0, range.location), markedText.utf16.count)
            if let character = layout.characters.first(where: { location < $0.range.upperBound }) {
                caret = (character.column, character.row)
            } else if let last = layout.characters.last {
                caret = (last.column + last.width, last.row)
            } else { return nil }
        } else { caret = layout.caret }
        guard caret.row >= 0 && caret.row < Int(size.rows) else { return nil }
        return ViewportCell(column: UInt16(caret.column), row: UInt32(caret.row))
    }

    /// Makes new quads for the rows that changed since the last call. Call it
    /// after `RenderState.update`, and `markClean` when the frame is drawn.
    @discardableResult
    public func prepare(from state: RenderState) throws -> FrameStatistics {
        let screenColors = state.colors
        colors = screenColors
        cursor = state.cursor
        columnCount = Int(state.size.columns)
        rowCount = Int(state.size.rows)
        grid = state.size
        reclaimedForFrame = false
        if atlas.isFull { _ = reclaimAtlas() }
        func update() throws -> FrameStatistics {
            try cache.update(from: state, colors: screenColors) {
                try RowQuads(row: $0, colors: screenColors, selection: selectionColor, atlas: atlas, metrics: fonts.metrics)
            }
        }
        let statistics = try update()
        if atlas.isFull, !reclaimedForFrame, reclaimAtlas() { return try update() }
        return statistics
    }

    private func reclaimAtlas() -> Bool {
        reclaimedForFrame = true
        guard atlas.reclaim() else { return false }
        cache.forget()
        drawnBands = nil
        return true
    }

    /// Draws the prepared rows into the target. The space around the grid and
    /// every cell without a background color get the background of the screen.
    ///
    /// - Returns: `false` when the graphics processor is behind, when the glyph
    ///   atlas needs a new frame, or when Metal could not make the commands.
    ///   The caller tries again at the next frame.
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
        guard let backing = backingTexture(matching: target.texture) else { return false }
        let marked = markedTextToDraw()
        if atlas.isFull && !reclaimedForFrame { return false }
        let flash = isFlashing ? colors.map { OverlayQuads.flash(width: target.texture.width, height: target.texture.height, color: $0.foreground) } : nil
        let frame = FrameBuilder(
            cache: cache, metrics: fonts.metrics, padding: padding, cursor: marked == nil ? cursorToDraw() : nil, markedText: marked, flash: flash)
        let bands = frame.bands(rowCount: rowCount, targetHeight: backing.height, metrics: fonts.metrics, padding: padding)
        let previous = drawnBands
        let rebuild = previous?.count != bands.count || drawnGrid != grid || drawnColors != colors || drawnSelectionColor != selectionColor
        let changed = bands.indices.filter { index in
            bands[index].bottom > bands[index].top && (rebuild || previous?[index] != bands[index])
        }
        let background = colors?.background ?? TerminalColor(red: 0, green: 0, blue: 0)
        let lists = changed.flatMap { index -> [[CellQuad]] in
            let band = bands[index]
            let clear = CellQuad.rectangle(horizontalPosition: 0, verticalPosition: band.top, width: backing.width, height: band.bottom - band.top, color: background)
            return [[clear] + band.backgrounds, band.glyphs, band.overlays]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = backing
        pass.colorAttachments[0].loadAction = previous == nil || bands.isEmpty ? .clear : .load
        pass.colorAttachments[0].storeAction = .store
        let clear = CellQuad.vector(background)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: 1)
        guard let (buffer, offsets) = copy(lists), let commands = queue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return false }
        var viewport = SIMD2<Float>(Float(target.texture.width), Float(target.texture.height))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.setFragmentTexture(atlas.coverage, index: 0)
        encoder.setFragmentTexture(atlas.color, index: 1)
        for (index, row) in changed.enumerated() {
            let band = bands[row]
            encoder.setScissorRect(MTLScissorRect(x: 0, y: band.top, width: backing.width, height: band.bottom - band.top))
            draw(lists[index * 3], with: shaders.rectangles, buffer: buffer, offset: offsets[index * 3], encoder: encoder)
            draw(lists[index * 3 + 1], with: shaders.glyphs, buffer: buffer, offset: offsets[index * 3 + 1], encoder: encoder)
            draw(lists[index * 3 + 2], with: shaders.rectangles, buffer: buffer, offset: offsets[index * 3 + 2], encoder: encoder)
        }
        encoder.endEncoding()
        let presentation = MTLRenderPassDescriptor()
        presentation.colorAttachments[0].texture = target.texture
        presentation.colorAttachments[0].loadAction = .dontCare
        presentation.colorAttachments[0].storeAction = .store
        guard let presentEncoder = commands.makeRenderCommandEncoder(descriptor: presentation) else { return false }
        var picture = CellQuad(origin: .zero, size: viewport, isColor: 1, color: SIMD4(repeating: 1))
        presentEncoder.setRenderPipelineState(shaders.glyphs)
        presentEncoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        presentEncoder.setVertexBytes(&picture, length: MemoryLayout<CellQuad>.stride, index: 1)
        presentEncoder.setFragmentTexture(backing, index: 0)
        presentEncoder.setFragmentTexture(backing, index: 1)
        presentEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        presentEncoder.endEncoding()
        (drawnBands, drawnGrid, drawnColors, drawnSelectionColor) = (bands, grid, colors, selectionColor)
        rowsDrawn = changed.count
        let finished = framesInFlight
        commands.addCompletedHandler { _ in finished.signal() }
        target.present(with: commands)
        commands.commit()
        reclaimedForFrame = false
        return true
    }

    private func backingTexture(matching target: MTLTexture) -> MTLTexture? {
        if let backing, backing.width == target.width, backing.height == target.height, backing.pixelFormat == target.pixelFormat { return backing }
        drawnBands = nil
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: target.pixelFormat, width: target.width, height: target.height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        backing = device.makeTexture(descriptor: descriptor)
        return backing
    }

    private func markedTextToDraw() -> MarkedTextQuads? {
        guard let markedText, !markedText.isEmpty, let colors, let position = cursor?.position else { return nil }
        return MarkedTextQuads(
            text: markedText, column: Int(position.column), row: Int(position.row), columnCount: columnCount, rowCount: rowCount, colors: colors,
            atlas: atlas, metrics: fonts.metrics, padding: padding, selection: markedTextSelection, selectionColor: selectionColor)
    }

    private func cursorToDraw() -> FrameBuilder.Cursor? {
        guard isCursorShown, let colors, let cursor, cursor.isVisible, let position = cursor.position else { return nil }
        return FrameBuilder.Cursor(
            column: Int(position.column), row: Int(position.row), style: isFocused ? cursor.style : .hollowBlock,
            isOnWideCharacterTail: cursor.isOnWideCharacterTail, color: colors.cursor ?? colors.foreground,
            textColor: colors.background, stroke: max(1, Int(fonts.scale.rounded())))
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
