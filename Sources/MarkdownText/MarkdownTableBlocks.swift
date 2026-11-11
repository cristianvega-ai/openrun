/// Tables in the form of GitHub Flavored Markdown.
extension MarkdownBlockParser {
    /// The header and alignments of a table that starts at this line.
    ///
    /// While the text streams, a row of cells at the end already shows as a
    /// table, so it does not show as a paragraph first and then change.
    func tableStart() -> (header: [String], alignments: [MarkdownTable.Alignment])? {
        guard let header = MarkdownTableLine.cells(lines[index]) else { return nil }
        if index + 1 < lines.count, let alignments = MarkdownTableLine.alignments(lines[index + 1]),
            alignments.count == header.count {
            return (header, alignments)
        }
        let startsWithPipe = MarkdownLine.trimmed(lines[index]).first == "|"
        let unfinished = isOpen(after: index)
            || (isOpen(after: index + 1) && MarkdownTableLine.couldBecomeDelimiter(lines[index + 1]))
        guard startsWithPipe, unfinished else { return nil }
        return (header, Array(repeating: .leading, count: header.count))
    }

    mutating func parseTable(_ start: (header: [String], alignments: [MarkdownTable.Alignment])) {
        let width = start.header.count
        index += 1
        // The delimiter row, or the start of one that streams.
        if index < lines.count { index += 1 }
        var rows: [[String]] = []
        while index < lines.count, !MarkdownLine.isBlank(lines[index]), let cells = MarkdownTableLine.cells(lines[index]) {
            let fitted = Array(cells.prefix(width)) + Array(repeating: "", count: max(0, width - cells.count))
            rows.append(fitted)
            index += 1
        }
        append(.table(MarkdownTable(header: start.header, alignments: start.alignments, rows: rows)))
    }

    func startsTableHere() -> Bool {
        MarkdownLine.trimmed(lines[index]).first == "|" && tableStart() != nil
    }
}
