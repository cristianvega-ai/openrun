/// Emphasis with `*` and `_`, and strikethrough with `~~`.
extension MarkdownInlineParser {
    mutating func emphasis(at index: Int, _ end: Int, _ style: MarkdownSpan.Style, _ link: String?) -> Int? {
        let mark = characters[index]
        let run = runLength(of: mark, at: index, end)
        let width = mark == "~" ? 2 : min(run, 3)
        // A mark opens only before text, and `_` only at the start of a
        // word, so `snake_case` and `2 * 3` stay as they are.
        let opens = index + run < end && !isWhiteSpace(at: index + run)
            && !(mark == "_" && isWordCharacter(at: index - 1)) && !(mark == "~" && run != 2)
        guard opens else {
            emit(String(repeating: mark, count: run), style, link)
            return index + run
        }
        let added: MarkdownSpan.Style = mark == "~" ? .strikethrough : width == 1 ? .italic : width == 2 ? .bold : [.bold, .italic]
        if let close = closer(of: mark, width: width, from: index + width, end) {
            parse((index + width)..<close, style: style.union(added), link: link)
            return close + width
        }
        if closesOptimistically(end) {
            parse((index + width)..<end, style: style.union(added), link: link)
            return end
        }
        emit(String(repeating: mark, count: run), style, link)
        return index + run
    }

    /// The start of the marks that close an emphasis of `width` marks.
    private func closer(of mark: Character, width: Int, from start: Int, _ end: Int) -> Int? {
        var index = start
        while index < end {
            let character = characters[index]
            if character == "\\" {
                index += 2
            } else if character == "`" {
                index = endOfCodeSpan(at: index, end)
            } else if character == mark {
                let run = runLength(of: mark, at: index, end)
                let closes = index > start && !isWhiteSpace(at: index - 1)
                    && !(mark == "_" && isWordCharacter(at: index + run))
                if closes, run == width { return index }
                // In `***`, the last marks close the outer emphasis, and the
                // first ones close an inner one.
                if closes, run >= 3, run > width { return index + run - width }
                index += run
            } else {
                index += 1
            }
        }
        return nil
    }

    /// The index after a code span that starts at `index`, or after its
    /// backticks when it does not close.
    func endOfCodeSpan(at index: Int, _ end: Int) -> Int {
        let length = runLength(of: "`", at: index, end)
        var search = index + length
        while search < end {
            let run = runLength(of: "`", at: search, end)
            if run == length { return search + run }
            search += max(run, 1)
        }
        return index + length
    }
}
