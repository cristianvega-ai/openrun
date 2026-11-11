/// The blocks of one Markdown text that can grow while it streams.
///
/// While the text streams, a last line that holds only marks, such as `#`,
/// `-` or the start of a code fence, waits for more text. It would
/// otherwise show as one kind of block and then change to another.
public struct MarkdownDocument: Sendable, Hashable {
    public private(set) var text = ""
    public private(set) var isComplete = true
    public private(set) var blocks: [MarkdownBlock] = []

    public init(text: String = "", isComplete: Bool = true) {
        update(text: text, isComplete: isComplete)
    }

    /// Takes the whole text as it is now.
    /// - Returns: The index of the first block that changed. The blocks
    ///   before it are the same as before.
    @discardableResult
    public mutating func update(text newText: String, isComplete newIsComplete: Bool) -> Int {
        let shown = Self.shownPart(of: newText, isComplete: newIsComplete)
        var parser = MarkdownBlockParser(lines: Self.lines(of: shown), isComplete: newIsComplete)
        parser.run()
        var firstChange = 0
        while firstChange < min(parser.blocks.count, blocks.count), parser.blocks[firstChange] == blocks[firstChange] {
            firstChange += 1
        }
        blocks = parser.blocks
        text = newText
        isComplete = newIsComplete
        return firstChange
    }

    /// The text without a last line that must wait for more text.
    static func shownPart(of text: String, isComplete: Bool) -> Substring {
        guard !isComplete, let lastLineEnd = text.utf8.lastIndex(of: UInt8(ascii: "\n")) else {
            return isComplete || !mustWait(text[...]) ? text[...] : text.prefix(0)
        }
        let last = text[text.index(after: lastLineEnd)...]
        return mustWait(last) ? text[..<lastLineEnd] : text[...]
    }

    private static func mustWait(_ line: Substring) -> Bool {
        var rest = MarkdownLine.trimmed(line)
        while let quoted = MarkdownLine.quoteContent(rest) { rest = MarkdownLine.trimmed(quoted) }
        if rest.hasPrefix("``") || rest.hasPrefix("~~~") { return true }
        return rest.count <= 12 && rest.allSatisfy { " \t#>*+-|:`~=_.)[]xX0123456789".contains($0) }
    }

    /// The lines of `text` without their line ends.
    private static func lines(of text: Substring) -> [Substring] {
        text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { bytes in
            let end = bytes.last == UInt8(ascii: "\r") ? bytes.index(before: bytes.endIndex) : bytes.endIndex
            return text[bytes.startIndex..<end]
        }
    }
}
