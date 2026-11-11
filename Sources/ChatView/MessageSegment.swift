import MarkdownText

/// A part of an agent's message that one row shows: a run of blocks that
/// are not code, or one code block.
///
/// A run ends at a code block or at a limit of blocks and bytes, so a long
/// message becomes many rows, and the view measures and draws only the
/// rows on the screen. The parts depend only on the blocks before them, so
/// a message that grows changes only its last parts.
enum MessageSegment: Equatable {
    case text(Range<Int>)
    case code(Int)

    static let blockLimit = 24
    static let byteLimit = 8 * 1024

    static func segments(of blocks: [MarkdownBlock]) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var start: Int?
        var byteCount = 0
        func endText(at end: Int) {
            if let first = start { segments.append(.text(first..<end)) }
            start = nil
            byteCount = 0
        }
        for (index, block) in blocks.enumerated() {
            if case .code = block.kind {
                endText(at: index)
                segments.append(.code(index))
                continue
            }
            if let first = start, index - first >= blockLimit || byteCount >= byteLimit { endText(at: index) }
            if start == nil { start = index }
            byteCount += block.estimatedByteCount
        }
        endText(at: blocks.count)
        return segments
    }
}

extension MarkdownBlock {
    /// About the bytes of the block's text.
    var estimatedByteCount: Int {
        switch kind {
        case .paragraph(let text), .heading(_, let text), .listItem(_, let text), .code(_, let text, _): text.utf8.count
        case .table(let table): (table.header + table.rows.joined()).reduce(0) { $0 + $1.utf8.count + 1 }
        case .rule: 1
        }
    }
}
