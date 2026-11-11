/// What a block of Markdown is.
public enum MarkdownBlockKind: Hashable, Sendable {
    /// Text with inline styles. A line break in it stays a line break.
    case paragraph(String)
    case heading(level: Int, text: String)
    /// The first paragraph of a list item. The other blocks of the item
    /// follow with the same list depth.
    case listItem(MarkdownListMarker, text: String)
    /// A fenced code block. `isClosed` is false while its end has not come.
    case code(language: String?, text: String, isClosed: Bool)
    case table(MarkdownTable)
    case rule
}
