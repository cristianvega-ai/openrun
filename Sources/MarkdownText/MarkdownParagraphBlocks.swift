/// Paragraphs: lines of text up to a blank line or the start of a block.
extension MarkdownBlockParser {
    /// A paragraph, cut into blocks of a limited size.
    mutating func parseParagraph(continuing: Bool) {
        var collected: [Substring] = []
        var byteCount = 0
        var continues = continuing
        while index < lines.count {
            let line = lines[index]
            if MarkdownLine.isBlank(line) { break }
            if !collected.isEmpty, Self.interruptsParagraph(line) || startsTableHere() { break }
            if collected.count >= Self.paragraphLineLimit || byteCount >= Self.paragraphByteLimit {
                append(.paragraph(collected.joined(separator: "\n")), continuesParagraph: continues)
                restartPoints.append(MarkdownRestartPoint(lineIndex: index, blockIndex: blocks.count, continuesParagraph: true))
                collected = []
                byteCount = 0
                continues = true
            }
            let text = MarkdownLine.trimmed(line)
            collected.append(text)
            byteCount += text.utf8.count + 1
            index += 1
        }
        append(.paragraph(collected.joined(separator: "\n")), continuesParagraph: continues)
    }
}
