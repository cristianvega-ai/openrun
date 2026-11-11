import AppKit

/// The open diff of a file change: at most 200 lines in a quiet box that
/// scrolls sideways, with the count of the other lines.
final class DiffBoxView: RoundedBoxView, MeasurableView {
    static let lineLimit = 200
    static let padding: CGFloat = 6
    let scrollView = SidewaysScrollView()
    let linesView = DiffLinesView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 6
        scrollView.documentView = linesView
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ diff: UnifiedDiff, palette: ChatPalette) {
        fillColor = palette.codeBackground
        let hidden = diff.lines.count - Self.lineLimit
        let note = hidden <= 0 ? nil : hidden == 1 ? "1 more line" : "\(hidden) more lines"
        linesView.show(Array(diff.lines.prefix(Self.lineLimit)), note: note, palette: palette)
        needsLayout = true
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        linesView.contentHeight + 2 * Self.padding
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 0, dy: Self.padding)
        linesView.frame = NSRect(x: 0, y: 0, width: max(linesView.contentWidth, scrollView.frame.width), height: linesView.contentHeight)
    }
}
