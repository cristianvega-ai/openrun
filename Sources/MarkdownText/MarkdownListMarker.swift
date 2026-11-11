/// The mark at the start of a list item.
public enum MarkdownListMarker: Hashable, Sendable {
    case bullet
    /// The number as the text writes it.
    case number(Int)
    /// A task list item, `- [ ]` or `- [x]`.
    case task(isDone: Bool)
}
