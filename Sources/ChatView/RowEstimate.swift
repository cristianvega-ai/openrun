import CoreGraphics

/// The height of a row before the view measures it.
///
/// A good estimate keeps the scroll bar steady while the user scrolls
/// through rows that have not been measured yet.
@MainActor enum RowEstimate {
    static func height(of row: TranscriptRow, width: CGFloat, context: TranscriptRowContext) -> CGFloat {
        let column = max(ChatColumn.frame(inWidth: width).width, 200)
        let lineHeight = (context.palette.bodyFont.pointSize * 1.45).rounded()
        switch row.kind {
        case .agentText(let item, let blocks):
            let document = context.documents[item]
            let bytes = blocks.reduce(0) { total, index in
                total + (document.map { index < $0.blocks.count ? $0.blocks[index].estimatedByteCount + 40 : 0 } ?? 0)
            }
            let charactersInALine = column / (context.palette.bodyFont.pointSize * 0.5)
            return (CGFloat(bytes) / charactersInALine).rounded(.up) * lineHeight
        case .agentCode(let item, let block):
            guard let document = context.documents[item], block < document.blocks.count,
                case .code(_, let text, _) = document.blocks[block].kind else { return 60 }
            return CGFloat(text.utf8.reduce(1) { $0 + ($1 == 10 ? 1 : 0) }) * 16 + 44
        case .userMessage: return lineHeight + 20
        case .toolCalls(let items): return CGFloat(min(items.count, 4)) * 26
        case .permissionRequest: return 160
        default: return 26
        }
    }
}
