/// Addresses in angle brackets and in plain text. Agents often write a
/// bare address, and a reader expects it to be a link.
extension MarkdownInlineParser {
    /// `<https://example.com>` or `<name@example.com>`.
    mutating func angleLink(at index: Int, _ end: Int, _ style: MarkdownSpan.Style, _ outer: String?) -> Int? {
        guard outer == nil else { return nil }
        var close = index + 1
        while close < end, characters[close] != ">", !characters[close].isWhitespace, characters[close] != "<" { close += 1 }
        guard close < end, characters[close] == ">", close > index + 1 else { return nil }
        let content = String(characters[(index + 1)..<close])
        let scheme = content.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) }
        if scheme.count >= 2, scheme.first?.isLetter == true, content.dropFirst(scheme.count).first == ":" {
            emit(content, style, content)
        } else if content.contains("@"), !content.contains(":") {
            emit(content, style, "mailto:" + content)
        } else {
            return nil
        }
        return close + 1
    }

    /// An `http` or `https` address in plain text. Punctuation at its end
    /// belongs to the sentence, as does a closing parenthesis that opens
    /// nowhere in the address.
    mutating func plainAddress(at index: Int, _ end: Int, _ style: MarkdownSpan.Style, _ outer: String?) -> Int? {
        guard outer == nil, !isWordCharacter(at: index - 1), index == 0 || characters[index - 1] != "/" else { return nil }
        let prefix = String(characters[index..<min(end, index + 8)])
        let schemeLength = prefix.hasPrefix("https://") ? 8 : prefix.hasPrefix("http://") ? 7 : 0
        guard schemeLength > 0 else { return nil }
        var stop = index + schemeLength
        while stop < end, !characters[stop].isWhitespace, !"<>\"`".contains(characters[stop]) { stop += 1 }
        while stop > index + schemeLength {
            let last = characters[stop - 1]
            let opened = characters[index..<stop].filter { $0 == "(" }.count
            let closed = characters[index..<stop].filter { $0 == ")" }.count
            guard ".,:;!?'*_~".contains(last) || (last == ")" && closed > opened) else { break }
            stop -= 1
        }
        guard stop > index + schemeLength else { return nil }
        let address = String(characters[index..<stop])
        emit(address, style, address)
        return stop
    }
}
