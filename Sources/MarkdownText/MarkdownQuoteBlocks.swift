/// Block quotes. The lines without their `>` are parsed again as Markdown,
/// one level deeper.
extension MarkdownBlockParser {
    mutating func parseQuote() {
        var content: [Substring] = []
        var previousIsText = false
        while index < lines.count {
            let line = lines[index]
            if let inner = MarkdownLine.quoteContent(line) {
                content.append(inner)
                previousIsText = !MarkdownLine.isBlank(inner)
            } else if previousIsText, !MarkdownLine.isBlank(line), !Self.interruptsParagraph(line) {
                content.append(MarkdownLine.trimmed(line))
            } else {
                break
            }
            index += 1
        }
        blocks.append(contentsOf: Self.blocks(
            of: content, isComplete: !isOpen(after: index - 1), listDepth: listDepth, quoteDepth: quoteDepth + 1))
    }
}
