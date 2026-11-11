/// The tests that tell which block a line of Markdown starts.
///
/// Each test reads one line without its line end. A tab counts as four
/// columns of indentation.
enum MarkdownLine {
    static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// The columns of white space at the start of the line.
    static func indentation(of line: Substring) -> Int {
        var columns = 0
        for character in line {
            if character == " " { columns += 1 } else if character == "\t" { columns += 4 } else { break }
        }
        return columns
    }

    /// The line without at most `columns` columns of white space at its start.
    static func removeIndentation(_ line: Substring, columns: Int) -> Substring {
        var removed = 0
        var start = line.startIndex
        while start < line.endIndex, removed < columns, line[start] == " " || line[start] == "\t" {
            removed += line[start] == "\t" ? 4 : 1
            start = line.index(after: start)
        }
        return line[start...]
    }

    static func trimmed(_ line: Substring) -> Substring {
        let start = line.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
        let end = line[start...].lastIndex { $0 != " " && $0 != "\t" }.map { line.index(after: $0) } ?? start
        return line[start..<end]
    }

    /// `# Title`: the level and the text without the closing marks.
    static func heading(_ line: Substring) -> (level: Int, text: Substring)? {
        guard indentation(of: line) < 4 else { return nil }
        let rest = trimmed(line)
        let level = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let after = rest.dropFirst(level)
        guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
        var text = trimmed(after)
        // A closing run of marks goes when white space comes before it.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0 {
            let before = text.dropLast(closing)
            if before.isEmpty || before.last == " " || before.last == "\t" { text = trimmed(before) }
        }
        return (level, text)
    }

    /// `---`, `***` or `___`, with optional spaces.
    static func isRule(_ line: Substring) -> Bool {
        guard indentation(of: line) < 4 else { return false }
        let marks = line.filter { $0 != " " && $0 != "\t" }
        guard let first = marks.first, "-*_".contains(first), marks.count >= 3 else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// The text of a block quote line without its `>`.
    static func quoteContent(_ line: Substring) -> Substring? {
        guard indentation(of: line) < 4 else { return nil }
        let rest = removeIndentation(line, columns: 3)
        guard rest.first == ">" else { return nil }
        let after = rest.dropFirst()
        return after.first == " " ? after.dropFirst() : after
    }
}
