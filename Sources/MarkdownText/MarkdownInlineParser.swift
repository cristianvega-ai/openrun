/// Reads the inline styles of the text of one block: emphasis, code spans,
/// strikethrough, links, and addresses in plain text.
///
/// While text streams, an emphasis, a code span or a link at its end that
/// has not closed yet already shows in its final form, so the text does not
/// change its look when the close comes.
public struct MarkdownInlineParser {
    let characters: [Character]
    /// Whether more text can come at the end.
    let isStreaming: Bool
    var spans: [MarkdownSpan] = []

    /// The spans of `text`. Each span holds the text that a reader sees,
    /// without the marks of the syntax.
    public static func spans(of text: String, isStreaming: Bool = false) -> [MarkdownSpan] {
        var parser = MarkdownInlineParser(characters: Array(text), isStreaming: isStreaming)
        parser.parse(0..<parser.characters.count, style: [], link: nil)
        return parser.spans
    }

    mutating func parse(_ range: Range<Int>, style: MarkdownSpan.Style, link: String?) {
        var index = range.lowerBound
        let end = range.upperBound
        while index < end {
            let next: Int? = switch characters[index] {
            case "\\": escape(at: index, end, style, link)
            case "`": codeSpan(at: index, end, style, link)
            case "*", "_", "~": emphasis(at: index, end, style, link)
            case "[": self.link(at: index, textStart: index + 1, end, style, link)
            case "!" where index + 1 < end && characters[index + 1] == "[":
                self.link(at: index, textStart: index + 2, end, style, link)
            case "<": angleLink(at: index, end, style, link)
            case "h": plainAddress(at: index, end, style, link)
            default: nil
            }
            if let next {
                index = next
            } else {
                emit(String(characters[index]), style, link)
                index += 1
            }
        }
    }

    /// Adds text to the last span when its style and link are the same.
    mutating func emit(_ text: String, _ style: MarkdownSpan.Style, _ link: String?) {
        guard !text.isEmpty else { return }
        if let last = spans.last, last.style == style, last.link == link {
            spans[spans.count - 1].text += text
        } else {
            spans.append(MarkdownSpan(text, style: style, link: link))
        }
    }

    /// Whether a construct that has not closed by `end` shows as closed.
    func closesOptimistically(_ end: Int) -> Bool {
        isStreaming && end == characters.count
    }

    /// The length of the run of `character` that starts at `index`.
    func runLength(of character: Character, at index: Int, _ end: Int) -> Int {
        var length = 0
        while index + length < end, characters[index + length] == character { length += 1 }
        return length
    }

    func isWhiteSpace(at index: Int) -> Bool {
        index < 0 || index >= characters.count || characters[index].isWhitespace
    }

    func isWordCharacter(at index: Int) -> Bool {
        index >= 0 && index < characters.count && (characters[index].isLetter || characters[index].isNumber)
    }

    private mutating func escape(at index: Int, _ end: Int, _ style: MarkdownSpan.Style, _ link: String?) -> Int? {
        guard index + 1 < end, characters[index + 1].isASCII, characters[index + 1].isPunctuation || characters[index + 1].isSymbol
        else { return nil }
        emit(String(characters[index + 1]), style, link)
        return index + 2
    }

    private mutating func codeSpan(at index: Int, _ end: Int, _ style: MarkdownSpan.Style, _ link: String?) -> Int? {
        let length = runLength(of: "`", at: index, end)
        var search = index + length
        while search < end {
            let run = runLength(of: "`", at: search, end)
            if run == length {
                emit(Self.codeText(characters[(index + length)..<search]), style.union(.code), link)
                return search + run
            }
            search += max(run, 1)
        }
        guard closesOptimistically(end) else {
            emit(String(repeating: "`", count: length), style, link)
            return index + length
        }
        emit(Self.codeText(characters[(index + length)..<end]), style.union(.code), link)
        return end
    }

    /// The content of a code span: line ends become spaces, and one space
    /// at each end goes when both ends have one.
    private static func codeText(_ characters: ArraySlice<Character>) -> String {
        var text = String(characters.map { $0 == "\n" ? " " : $0 })
        if text.count >= 2, text.first == " ", text.last == " ", text.contains(where: { $0 != " " }) {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }
}
