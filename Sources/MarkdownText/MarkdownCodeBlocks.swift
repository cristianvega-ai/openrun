/// Fenced code blocks. A block whose closing fence has not come runs to the
/// end of the text, so code that streams in shows as code at once.
extension MarkdownBlockParser {
    mutating func parseCode(_ fence: MarkdownFence) {
        index += 1
        var content: [Substring] = []
        var isClosed = false
        while index < lines.count {
            let line = lines[index]
            index += 1
            if fence.isClosed(by: line) {
                isClosed = true
                break
            }
            content.append(MarkdownLine.removeIndentation(line, columns: fence.indentation))
        }
        append(.code(language: fence.language, text: content.joined(separator: "\n"), isClosed: isClosed))
    }
}
