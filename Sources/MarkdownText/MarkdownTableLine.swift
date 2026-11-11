/// The rows of a table: `| a | b |`, and the delimiter row `|---|:-:|`.
enum MarkdownTableLine {
    /// The cells of a row, or nil when the line has no pipe outside code.
    static func cells(_ line: Substring) -> [String]? {
        guard MarkdownLine.indentation(of: line) < 4 else { return nil }
        var cells: [String] = []
        var cell = ""
        var hasPipe = false
        var inCode = false
        var escaped = false
        for character in MarkdownLine.trimmed(line) {
            if escaped {
                // `\|` keeps a pipe in a cell. Other escapes stay for the
                // inline parser.
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "`" {
                inCode.toggle()
                cell.append(character)
            } else if character == "|", !inCode {
                hasPipe = true
                cells.append(cell)
                cell = ""
            } else {
                cell.append(character)
            }
        }
        if escaped { cell.append("\\") }
        guard hasPipe else { return nil }
        cells.append(cell)
        // A pipe at the start or the end of the row only frames it.
        if cells.first.map(isBlank) == true { cells.removeFirst() }
        if cells.count > 1, cells.last.map(isBlank) == true { cells.removeLast() }
        return cells.map { String(MarkdownLine.trimmed($0[...])) }
    }

    /// The alignments of a delimiter row, such as `| --- | :-: | --: |`.
    static func alignments(_ line: Substring) -> [MarkdownTable.Alignment]? {
        guard let cells = cells(line), !cells.isEmpty else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in cells {
            let leading = cell.hasPrefix(":")
            let trailing = cell.hasSuffix(":") && cell.count > 1
            let dashes = cell.dropFirst(leading ? 1 : 0).dropLast(trailing ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(leading && trailing ? .center : trailing ? .trailing : .leading)
        }
        return alignments
    }

    /// Whether the line could still become a delimiter row as more text
    /// comes, such as `|--` while it streams.
    static func couldBecomeDelimiter(_ line: Substring) -> Bool {
        let rest = MarkdownLine.trimmed(line)
        return !rest.isEmpty && rest.allSatisfy { "|:- \t".contains($0) }
    }

    private static func isBlank(_ text: String) -> Bool {
        MarkdownLine.isBlank(text[...])
    }
}
