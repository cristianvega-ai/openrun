import Foundation

/// Links, `[text](target)`, and images, which show as links. A link is
/// only data here. Nothing opens it.
extension MarkdownInlineParser {
    mutating func link(at index: Int, textStart: Int, _ end: Int, _ style: MarkdownSpan.Style, _ outer: String?) -> Int? {
        guard outer == nil else { return nil }
        guard let close = matchingBracket(from: textStart, end) else {
            // `[text` at the end of a stream is a link that comes.
            guard closesOptimistically(end), textStart < end, !isWordCharacter(at: index - 1) else { return nil }
            parse(textStart..<end, style: style, link: "")
            return end
        }
        if close + 1 < end, characters[close + 1] == "(" {
            if let parenthesis = matchingParenthesis(from: close + 2, end) {
                parse(textStart..<close, style: style, link: Self.target(characters[(close + 2)..<parenthesis]))
                return parenthesis + 1
            }
            guard closesOptimistically(end) else { return nil }
            parse(textStart..<close, style: style, link: "")
            return end
        }
        guard close + 1 == end, closesOptimistically(end), !isWordCharacter(at: index - 1) else { return nil }
        parse(textStart..<close, style: style, link: "")
        return end
    }

    private func matchingBracket(from start: Int, _ end: Int) -> Int? {
        var depth = 0
        var index = start
        while index < end {
            switch characters[index] {
            case "\\": index += 1
            case "`": index = endOfCodeSpan(at: index, end) - 1
            case "[": depth += 1
            case "]":
                if depth == 0 { return index }
                depth -= 1
            default: break
            }
            index += 1
        }
        return nil
    }

    private func matchingParenthesis(from start: Int, _ end: Int) -> Int? {
        var depth = 0
        var index = start
        while index < end {
            switch characters[index] {
            case "\\": index += 1
            case "(": depth += 1
            case ")":
                if depth == 0 { return index }
                depth -= 1
            case "\n": return nil
            default: break
            }
            index += 1
        }
        return nil
    }

    /// The target without its angle brackets and its title.
    private static func target(_ characters: ArraySlice<Character>) -> String {
        let text = String(characters).trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("<"), let close = text.firstIndex(of: ">") {
            return String(text[text.index(after: text.startIndex)..<close])
        }
        return String(text.prefix { !$0.isWhitespace })
    }
}
