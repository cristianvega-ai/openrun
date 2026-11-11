/// A table in the form of GitHub Flavored Markdown.
public struct MarkdownTable: Hashable, Sendable {
    public enum Alignment: Hashable, Sendable {
        case leading, center, trailing
    }

    public var header: [String]
    /// One alignment for each column of the header.
    public var alignments: [Alignment]
    /// Each row has as many cells as the header.
    public var rows: [[String]]

    public init(header: [String], alignments: [Alignment], rows: [[String]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }
}
