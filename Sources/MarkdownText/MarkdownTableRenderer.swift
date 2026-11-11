import AppKit

/// A table as a TextKit text table: one paragraph for each cell, with thin
/// lines between the cells and a quiet background behind the header.
struct MarkdownTableRenderer {
    let style: MarkdownStyle
    let isStreaming: Bool

    /// The cells of the table. Each cell ends with a line end but the last.
    func attributedString(_ table: MarkdownTable, spacingBefore: CGFloat) -> NSAttributedString {
        let textTable = NSTextTable()
        textTable.numberOfColumns = max(1, table.header.count)
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.setWidth(spacingBefore, type: .absoluteValueType, for: .margin, edge: .minY)
        let result = NSMutableAttributedString()
        let rows = [table.header] + table.rows
        for (rowIndex, row) in rows.enumerated() {
            for (column, cell) in row.enumerated() {
                let isLast = rowIndex == rows.count - 1 && column == row.count - 1
                let alignment = column < table.alignments.count ? table.alignments[column] : .leading
                result.append(self.cell(
                    cell, row: rowIndex, column: column, alignment: alignment, table: textTable, endsWithLineEnd: !isLast))
            }
        }
        return result
    }

    private func cell(
        _ text: String, row: Int, column: Int, alignment: MarkdownTable.Alignment, table: NSTextTable, endsWithLineEnd: Bool
    ) -> NSAttributedString {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(style.dividerColor)
        let size = style.bodyFont.pointSize
        block.setWidth((size * 0.6).rounded(), type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth((size * 0.6).rounded(), type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth((size * 0.3).rounded(), type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth((size * 0.3).rounded(), type: .absoluteValueType, for: .padding, edge: .maxY)
        if row == 0 { block.backgroundColor = style.tableHeaderBackgroundColor }
        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [block]
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        paragraph.alignment = switch alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
        let font = row == 0 ? style.font(for: .bold, base: style.bodyFont) : style.bodyFont
        let content = MarkdownInlineRenderer.attributedString(
            text, isStreaming: isStreaming && endsWithLineEnd == false, font: font, color: style.textColor, style: style)
        // An empty cell still needs a character, or it takes no room.
        if content.length == 0 { content.append(NSAttributedString(string: "\u{200B}", attributes: [.font: font])) }
        if endsWithLineEnd { content.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
        content.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: content.length))
        return content
    }
}
