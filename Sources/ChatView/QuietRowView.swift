import AppKit

/// A quiet row that is no tool call, such as a notice or a failed turn: a
/// line that opens to its details when it has any.
final class QuietRowView: StackRowView {
    let line = DisclosureLineView()
    private lazy var detailBox = DetailBoxView()

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        guard let content = row.items.first.flatMap(context.item), let words = QuietLine(content) else { return }
        line.show(symbolName: words.symbolName, title: words.title, status: words.status, palette: context.palette)
        line.action = words.details.isEmpty ? nil : { [weak self, weak context] in
            guard let self else { return }
            context?.actions?.toggle(row.key, in: self)
        }
        line.isOpen = !words.details.isEmpty && context.openedParts.contains(row.key)
        if line.isOpen { detailBox.show(words.details.map { ($0, nil) }, palette: context.palette) }
        setParts(line.isOpen ? [Part(view: line), Part(view: detailBox, indentation: 24)] : [Part(view: line)])
        setAccessibilityRole(.group)
        setAccessibilityLabel(words.kindLabel)
    }
}
