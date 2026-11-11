import AppKit

/// A row of quiet lines and the boxes that open under them, one above the
/// other, such as a run of tool calls or a file change.
class StackRowView: TranscriptRowView {
    struct Part {
        var view: NSView
        var indentation: CGFloat = 0
    }

    private(set) var parts: [Part] = []

    /// Shows the parts from the top. A view that is no part leaves the row.
    func setParts(_ newParts: [Part]) {
        for view in subviews where !newParts.contains(where: { $0.view === view }) { view.removeFromSuperview() }
        for part in newParts where part.view.superview !== self { addSubview(part.view) }
        parts = newParts
        needsLayout = true
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        frames(forWidth: width).last?.maxY ?? 0
    }

    /// A line stands 6 points left of the column, so its symbol lines up
    /// with the text and the fill under the pointer has room.
    private func frames(forWidth width: CGFloat) -> [NSRect] {
        let column = ChatColumn.frame(inWidth: width)
        var top: CGFloat = 0
        return parts.map { part in
            let isBox = !(part.view is DisclosureLineView)
            let x = column.x + part.indentation - (isBox ? 0 : 6)
            let partWidth = column.width - part.indentation + (isBox ? 0 : 6)
            let height = isBox ? Self.height(of: part.view, width: partWidth) : DisclosureLineView.height
            let frame = NSRect(x: x, y: top + (isBox ? 2 : 0), width: partWidth, height: height)
            top = frame.maxY + (isBox ? 6 : 0)
            return frame
        }
    }

    private static func height(of view: NSView, width: CGFloat) -> CGFloat {
        (view as? DetailBoxView)?.height(forWidth: width) ?? view.fittingSize.height
    }

    override func layout() {
        super.layout()
        for (part, frame) in zip(parts, frames(forWidth: bounds.width)) { part.view.frame = frame }
    }
}
