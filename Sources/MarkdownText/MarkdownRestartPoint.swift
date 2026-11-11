/// A place in the lines of a text where a parse of the blocks can start
/// again with the same result.
struct MarkdownRestartPoint: Equatable {
    var lineIndex: Int
    var blockIndex: Int
    /// The line goes on with a paragraph that the parser cut.
    var continuesParagraph: Bool
}
