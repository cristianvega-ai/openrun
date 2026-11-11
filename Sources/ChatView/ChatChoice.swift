/// One entry of a menu of the chat, such as a model or a permission mode.
public struct ChatChoice: Equatable, Hashable, Sendable {
    /// The value that the host knows, such as `claude-opus-5-5` or `plan`.
    public var identifier: String
    /// The words that the menu shows, such as "Opus 5.5" or "Plan".
    public var title: String

    public init(identifier: String, title: String) {
        self.identifier = identifier
        self.title = title
    }
}
