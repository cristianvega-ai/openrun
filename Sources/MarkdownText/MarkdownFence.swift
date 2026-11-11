/// The opening line of a fenced code block, such as ` ```swift `.
struct MarkdownFence: Equatable {
    /// A backtick or a tilde.
    var character: Character
    var length: Int
    /// The indentation of the opening line. Content lines lose as much.
    var indentation: Int
    /// The first word after the fence, such as `swift`.
    var language: String?

    init?(_ line: Substring) {
        indentation = MarkdownLine.indentation(of: line)
        guard indentation < 4 else { return nil }
        let rest = MarkdownLine.trimmed(line)
        guard let first = rest.first, first == "`" || first == "~" else { return nil }
        character = first
        length = rest.prefix { $0 == first }.count
        guard length >= 3 else { return nil }
        let information = MarkdownLine.trimmed(rest.dropFirst(length))
        // A backtick in the information would make it inline code.
        if first == "`", information.contains("`") { return nil }
        let word = information.prefix { $0 != " " && $0 != "\t" && $0 != "{" }
        language = word.isEmpty ? nil : String(word)
    }

    /// Whether `line` closes the block that this fence opened.
    func isClosed(by line: Substring) -> Bool {
        guard MarkdownLine.indentation(of: line) < 4 else { return false }
        let rest = MarkdownLine.trimmed(line)
        return rest.count >= length && rest.allSatisfy { $0 == character }
    }
}
