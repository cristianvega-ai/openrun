/// The start of a list item: `- `, `* `, `+ `, `1. ` or `1) `.
struct MarkdownListItemStart: Equatable {
    var marker: MarkdownListMarker
    /// The indentation of the marker.
    var markerColumn: Int
    /// The column where the content of the item starts. Later lines of the
    /// item are indented at least this far.
    var contentColumn: Int
    /// The rest of the first line, without a task box.
    var content: Substring

    var isEmpty: Bool { MarkdownLine.isBlank(content) }

    init?(_ line: Substring) {
        markerColumn = MarkdownLine.indentation(of: line)
        guard markerColumn < 4 else { return nil }
        let rest = MarkdownLine.removeIndentation(line, columns: markerColumn)
        var markerWidth: Int
        if let first = rest.first, "-*+".contains(first) {
            marker = .bullet
            markerWidth = 1
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count), let number = Int(digits) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard after.first == "." || after.first == ")" else { return nil }
            marker = .number(number)
            markerWidth = digits.count + 1
        }
        let afterMarker = rest.dropFirst(markerWidth)
        guard afterMarker.isEmpty || afterMarker.first == " " || afterMarker.first == "\t" else { return nil }
        let spaces = MarkdownLine.indentation(of: afterMarker)
        // More than four spaces would start indented code, which a chat
        // never needs, so the content starts after one space then.
        let gap = afterMarker.isEmpty ? 1 : (spaces > 4 || MarkdownLine.isBlank(afterMarker) ? 1 : spaces)
        contentColumn = markerColumn + markerWidth + gap
        content = MarkdownLine.removeIndentation(afterMarker, columns: gap)
        if let task = Self.task(in: content) {
            marker = .task(isDone: task.isDone)
            content = task.rest
        }
    }

    private static func task(in content: Substring) -> (isDone: Bool, rest: Substring)? {
        let prefix = content.prefix(4)
        guard prefix.count >= 3, prefix.first == "[", prefix.dropFirst(2).first == "]" else { return nil }
        guard prefix.count == 3 || prefix.last == " " else { return nil }
        switch prefix.dropFirst().first {
        case " ": return (false, content.dropFirst(prefix.count))
        case "x", "X": return (true, content.dropFirst(prefix.count))
        default: return nil
        }
    }
}
