import TerminalEmulation

/// The quads of one frame, in the order of drawing: the backgrounds, the glyphs,
/// and then the lines on top of the glyphs.
struct FrameBuilder {
    /// The cursor as the renderer shows it.
    struct Cursor {
        let column: Int
        let row: Int
        let style: CursorStyle
        let isOnWideCharacterTail: Bool
        let color: TerminalColor
        /// The color of the glyph in a block cursor, so that it stays readable.
        let textColor: TerminalColor
        let stroke: Int
    }

    struct Band: Equatable {
        let top, bottom: Int
        var backgrounds: [CellQuadrilateral] = []
        var glyphs: [CellQuadrilateral] = []
        var overlays: [CellQuadrilateral] = []
    }

    /// Includes a quad in every band that its pixels can reach.
    static func bandIndices(of quad: CellQuadrilateral, rowCount: Int, targetHeight: Int, metrics: CellMetrics, padding: Int) -> ClosedRange<Int>? {
        guard rowCount > 0 else { return nil }
        let top = max(0, Int(quad.origin.y))
        let bottom = min(targetHeight, Int(quad.origin.y + quad.size.y))
        guard top < bottom else { return nil }
        let first = max(0, min(rowCount - 1, (top - padding) / metrics.height))
        let last = max(0, min(rowCount - 1, (bottom - 1 - padding) / metrics.height))
        return first...last
    }

    func bands(rowCount: Int, targetHeight: Int, metrics: CellMetrics, padding: Int) -> [Band] {
        guard rowCount > 0 else { return [] }
        var bands = (0..<rowCount).map { index in
            Band(top: index == 0 ? 0 : min(targetHeight, padding + index * metrics.height),
                 bottom: index == rowCount - 1 ? targetHeight : min(targetHeight, padding + (index + 1) * metrics.height))
        }
        func add(_ list: [CellQuadrilateral], to field: WritableKeyPath<Band, [CellQuadrilateral]>) {
            for quad in list {
                guard let indices = Self.bandIndices(of: quad, rowCount: rowCount, targetHeight: targetHeight, metrics: metrics, padding: padding) else { continue }
                for index in indices { bands[index][keyPath: field].append(quad) }
            }
        }
        add(backgrounds, to: \.backgrounds)
        add(glyphs, to: \.glyphs)
        add(overlays, to: \.overlays)
        return bands
    }

    private(set) var backgrounds: [CellQuadrilateral] = []
    private(set) var glyphs: [CellQuadrilateral] = []
    private(set) var overlays: [CellQuadrilateral] = []

    /// Moves the quads of each row to its place on the screen: down by the
    /// rows above it, and in by the space around the grid.
    init(cache: RowCache, metrics: CellMetrics, padding: Int, cursor: Cursor? = nil, markedText: MarkedTextQuadrilaterals? = nil, flash: CellQuadrilateral? = nil) {
        for index in cache.order.indices {
            guard let row = cache.quads(at: index) else { continue }
            let top = padding + index * metrics.height
            let glyphStart = glyphs.count
            backgrounds += row.backgrounds.map { $0.moved(horizontalOffset: padding, verticalOffset: top) }
            // The background of marked text hides the glyphs under it.
            let covered = markedText?.coveredColumns[index]
            let visible = covered.map { columns in
                row.glyphs.filter { glyph in
                    let start = Int(glyph.column)
                    let width = row.wideColumns.contains(UInt16(glyph.column)) ? 2 : 1
                    return !columns.overlaps(start..<start + width)
                }
            } ?? row.glyphs
            glyphs += visible.map { $0.moved(horizontalOffset: padding, verticalOffset: top) }
            let decorations = covered.map { columns in
                row.decorations.filter { line in
                    line.origin.x + line.size.x <= Float(columns.lowerBound * metrics.width)
                        || line.origin.x >= Float(columns.upperBound * metrics.width)
                }
            } ?? row.decorations
            overlays += decorations.map { $0.moved(horizontalOffset: padding, verticalOffset: top) }
            guard let cursor, cursor.row == index else { continue }
            // On the second cell of a wide character, the cursor starts one column to the left.
            let column = cursor.column - (cursor.isOnWideCharacterTail ? 1 : 0)
            let isWide = cursor.isOnWideCharacterTail || row.wideColumns.contains(UInt16(column))
            let quads = CursorQuadrilaterals(
                style: cursor.style, horizontalPosition: padding + column * metrics.width, verticalPosition: top,
                width: (isWide ? 2 : 1) * metrics.width, height: metrics.height, stroke: cursor.stroke, color: cursor.color)
            backgrounds += quads.backgrounds
            overlays += quads.overlays
            if cursor.style == .block, let glyph = glyphs[glyphStart...].firstIndex(where: { Int($0.column) == column }) {
                glyphs[glyph].color = CellQuadrilateral.vector(cursor.textColor)
            }
        }
        if let markedText {
            backgrounds += markedText.backgrounds
            glyphs += markedText.glyphs
            overlays += markedText.overlays
        }
        if let flash { overlays.append(flash) }
    }
}
