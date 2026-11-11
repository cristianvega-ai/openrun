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

    private mutating func escape(at index: Int, _ end: Int, _ style: MarkdownSpan.Style, _ link: String?) -> Int? {
        guard index + 1 < end, characters[index + 1].isASCII, characters[index + 1].isPunctuation || characters[index + 1].isSymbol
        else { return nil }
        emit(String(characters[index + 1]), style, link)
        return index + 2
    }
}
