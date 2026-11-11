/// Paragraphs: lines of text up to a blank line or the start of a block.
extension MarkdownBlockParser {
    mutating func parseParagraph() {
        var collected: [Substring] = []
        while index < lines.count {
            let line = lines[index]
            if MarkdownLine.isBlank(line) { break }
            if !collected.isEmpty, Self.interruptsParagraph(line) || startsTableHere() { break }
            collected.append(MarkdownLine.trimmed(line))
            index += 1
        }
        append(.paragraph(collected.joined(separator: "\n")))
    }
}
