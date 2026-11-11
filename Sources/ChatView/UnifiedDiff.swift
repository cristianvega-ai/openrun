/// The lines of a unified diff and the count of added and removed lines.
struct UnifiedDiff: Equatable {
    enum LineKind: Equatable {
        case hunk, added, removed, context
    }

    struct Line: Equatable {
        var kind: LineKind
        /// The text without its mark of `+`, `-` or a space.
        var text: Substring
    }

    private(set) var lines: [Line] = []
    private(set) var addedCount = 0
    private(set) var removedCount = 0

    init(_ diff: String) {
        var isInHunk = false
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            // The lines before the first hunk name the files, which the row
            // shows already.
            if line.hasPrefix("@@") {
                isInHunk = true
                lines.append(Line(kind: .hunk, text: line))
                continue
            }
            guard isInHunk, let mark = line.first else { continue }
            switch mark {
            case "+":
                addedCount += 1
                lines.append(Line(kind: .added, text: line.dropFirst()))
            case "-":
                removedCount += 1
                lines.append(Line(kind: .removed, text: line.dropFirst()))
            case "\\": lines.append(Line(kind: .hunk, text: line))
            default: lines.append(Line(kind: .context, text: line.dropFirst()))
            }
        }
    }

    /// The change from `old` to `new`, such as an edit that an agent asks
    /// to make. The lines that both start and end with stay as context.
    /// - Parameter title: The first line, such as "Edit 1 of 2".
    init(old: String, new: String, title: String?) {
        let oldLines = old.isEmpty ? [] : old.split(separator: "\n", omittingEmptySubsequences: false)
        let newLines = new.isEmpty ? [] : new.split(separator: "\n", omittingEmptySubsequences: false)
        let start = zip(oldLines, newLines).prefix { $0 == $1 }.count
        let end = zip(oldLines.dropFirst(start).reversed(), newLines.dropFirst(start).reversed()).prefix { $0 == $1 }.count
        if let title { lines.append(Line(kind: .hunk, text: Substring(title))) }
        lines += oldLines.prefix(start).map { Line(kind: .context, text: $0) }
        lines += oldLines.dropFirst(start).dropLast(end).map { Line(kind: .removed, text: $0) }
        lines += newLines.dropFirst(start).dropLast(end).map { Line(kind: .added, text: $0) }
        lines += oldLines.suffix(end).map { Line(kind: .context, text: $0) }
        removedCount = oldLines.count - start - end
        addedCount = newLines.count - start - end
    }

    /// Changes the text of each line, such as to show hidden characters.
    mutating func mapText(_ transform: (Substring) -> Substring) {
        for index in lines.indices { lines[index].text = transform(lines[index].text) }
    }

    /// Keeps the lines that fit in `limit` characters.
    /// - Returns: The number of characters that do not show.
    mutating func cut(toCharacters limit: Int) -> Int {
        var used = 0
        let kept = lines.prefix { line in
            used += line.text.utf16.count + 1
            return used <= limit
        }.count
        let hidden = lines.dropFirst(kept).reduce(0) { $0 + $1.text.utf16.count + 1 }
        lines.removeLast(lines.count - kept)
        return hidden
    }

    mutating func append(_ other: UnifiedDiff) {
        lines += other.lines
        addedCount += other.addedCount
        removedCount += other.removedCount
    }

    /// The counts as a quiet label, such as "+3 −1".
    var countText: String {
        "+\(addedCount) \u{2212}\(removedCount)"
    }
}
