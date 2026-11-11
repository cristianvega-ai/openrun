import AgentConversation
import AppKit

/// A change of a file as a quiet line with the path and the counts of
/// added and removed lines. The line opens to the diff.
final class FileChangeRowView: StackRowView {
    let line = DisclosureLineView()
    private lazy var diffBox = DiffBoxView()

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        guard case .fileChange(let change)? = row.items.first.flatMap(context.item) else { return }
        let diff = UnifiedDiff(change.diff)
        let (symbol, verb) = switch change.kind {
        case .added: ("doc.badge.plus", "Created")
        case .modified: ("pencil", "Edited")
        case .deleted: ("trash", "Deleted")
        }
        line.show(symbolName: symbol, title: Self.shortPath(change.path), status: diff.countText, palette: context.palette)
        line.setAccessibilityLabel("\(verb) \(change.path), \(diff.addedCount) lines added, \(diff.removedCount) removed")
        line.toolTip = change.path
        line.isOpen = context.openedParts.contains(row.key)
        line.action = { [weak self, weak context] in
            guard let self else { return }
            context?.actions?.toggle(row.key, in: self)
        }
        if line.isOpen { diffBox.show(diff, palette: context.palette) }
        setParts(line.isOpen ? [Part(view: line), Part(view: diffBox, indentation: 24)] : [Part(view: line)])
        setAccessibilityRole(.group)
        setAccessibilityLabel("File change")
    }

    /// The last three parts of a path, which name the file and its place
    /// in the project. The full path shows to VoiceOver and in the tip.
    static func shortPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        return parts.count > 3 ? "…/" + parts.suffix(3).joined(separator: "/") : path
    }
}
