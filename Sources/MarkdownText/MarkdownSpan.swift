/// A run of text with one inline style, such as a bold word or a link.
public struct MarkdownSpan: Hashable, Sendable {
    public struct Style: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let bold = Style(rawValue: 1 << 0)
        public static let italic = Style(rawValue: 1 << 1)
        public static let code = Style(rawValue: 1 << 2)
        public static let strikethrough = Style(rawValue: 1 << 3)
    }

    public var text: String
    public var style: Style
    /// The target of a link as the text writes it. It is only data: a view
    /// opens it only when the user asks. An empty target is a link whose
    /// target has not streamed in yet.
    public var link: String?

    public init(_ text: String, style: Style = [], link: String? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }
}
