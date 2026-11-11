/// List items. The content of an item is parsed again as Markdown, one
/// level deeper, and its first paragraph carries the mark of the item.
extension MarkdownBlockParser {
    mutating func parseListItem(_ start: MarkdownListItemStart) {
        var content: [Substring] = [start.content]
        index += 1
        var previousIsBlank = start.isEmpty
        while index < lines.count {
            let line = lines[index]
            if MarkdownLine.isBlank(line) {
                content.append("")
                previousIsBlank = true
                index += 1
                continue
            }
            let indentation = MarkdownLine.indentation(of: line)
            // Agents often indent a nested list by two spaces under `1. `,
            // which CommonMark would read as a new list at the same level.
            let nested = MarkdownListItemStart(line) != nil && indentation >= start.markerColumn + 2
            if indentation >= start.contentColumn || nested {
                content.append(MarkdownLine.removeIndentation(line, columns: min(indentation, start.contentColumn)))
            } else if !previousIsBlank, !Self.interruptsParagraph(line) {
                // A lazy line goes on with the paragraph before it.
                content.append(MarkdownLine.trimmed(line))
            } else {
                break
            }
            previousIsBlank = false
            index += 1
        }
        while content.count > 1, content.last.map(MarkdownLine.isBlank) == true { content.removeLast() }
        var inner = Self.blocks(of: content, isComplete: !isOpen(after: index - 1), listDepth: listDepth + 1, quoteDepth: quoteDepth)
        if case .paragraph(let text)? = inner.first?.kind, inner.first?.continuesParagraph == false {
            inner[0].kind = .listItem(start.marker, text: text)
        } else {
            inner.insert(MarkdownBlock(.listItem(start.marker, text: ""), listDepth: listDepth + 1, quoteDepth: quoteDepth), at: 0)
        }
        blocks.append(contentsOf: inner)
    }
}
