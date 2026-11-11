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

    /// The counts as a quiet label, such as "+3 −1".
    var countText: String {
        "+\(addedCount) \u{2212}\(removedCount)"
    }
}
