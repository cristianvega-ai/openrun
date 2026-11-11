/// One block of a Markdown text, such as a paragraph or a code block.
///
/// The blocks of a text are flat. A block inside a list item or a block
/// quote carries its depth, so a view can show each block in a row of its
/// own and still indent it.
public struct MarkdownBlock: Hashable, Sendable {
    public var kind: MarkdownBlockKind
    /// How many list items hold the block.
    public var listDepth: Int
    /// How many block quotes hold the block.
    public var quoteDepth: Int
    /// Whether the block goes on from the paragraph before it. The parser
    /// cuts a long paragraph into parts, so that text which streams in
    /// changes only a small last part.
    public var continuesParagraph: Bool

    public init(_ kind: MarkdownBlockKind, listDepth: Int = 0, quoteDepth: Int = 0, continuesParagraph: Bool = false) {
        self.kind = kind
        self.listDepth = listDepth
        self.quoteDepth = quoteDepth
        self.continuesParagraph = continuesParagraph
    }
}
