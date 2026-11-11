/// Splits Markdown text into blocks, one line at a time.
///
/// It reads the part of CommonMark and of GitHub's tables that coding
/// agents write. It never looks back: once the next block starts, a block
/// is final. So text that streams in changes only the last blocks, and a
/// parse can start again at the start of a block at the top level.
struct MarkdownBlockParser {
    let lines: [Substring]
    /// Whether no more text can come after the last line.
    let isComplete: Bool
    let listDepth: Int
    let quoteDepth: Int
    var index = 0
    var blocks: [MarkdownBlock] = []

    init(lines: [Substring], isComplete: Bool, listDepth: Int = 0, quoteDepth: Int = 0) {
        self.lines = lines
        self.isComplete = isComplete
        self.listDepth = listDepth
        self.quoteDepth = quoteDepth
    }

    mutating func run() {
        while index < lines.count {
            let line = lines[index]
            if MarkdownLine.isBlank(line) {
                index += 1
                continue
            }
            if let fence = MarkdownFence(line) {
                parseCode(fence)
            } else if let heading = MarkdownLine.heading(line) {
                append(.heading(level: heading.level, text: String(heading.text)))
                index += 1
            } else if MarkdownLine.isRule(line) {
                append(.rule)
                index += 1
            } else if let table = tableStart() {
                parseTable(table)
            } else {
                parseParagraph()
            }
        }
    }

    mutating func append(_ kind: MarkdownBlockKind, continuesParagraph: Bool = false) {
        blocks.append(MarkdownBlock(kind, listDepth: listDepth, quoteDepth: quoteDepth, continuesParagraph: continuesParagraph))
    }

    /// Whether more text can still come after the line at `lineIndex`.
    func isOpen(after lineIndex: Int) -> Bool {
        !isComplete && lineIndex >= lines.count - 1
    }

    /// Whether the line starts a block and so ends a paragraph before it.
    static func interruptsParagraph(_ line: Substring) -> Bool {
        MarkdownFence(line) != nil || MarkdownLine.heading(line) != nil || MarkdownLine.isRule(line)
    }
}
