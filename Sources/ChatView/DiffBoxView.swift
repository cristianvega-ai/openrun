import AppKit

/// The open diff of a file change: every line, in a quiet box of bounded
/// height that scrolls inside, up and down and sideways.
final class DiffBoxView: RoundedBoxView, MeasurableView {
    static let padding: CGFloat = 6
    static let maximumHeight: CGFloat = 360
    /// The height of the lines above which they scroll.
    var heightLimit = DiffBoxView.maximumHeight
    let scrollView = InnerScrollView()
    let linesView = DiffLinesView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 6
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = linesView
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ diff: UnifiedDiff, palette: ChatPalette) {
        fillColor = palette.codeBackground
        linesView.show(diff.lines, note: nil, palette: palette)
        needsLayout = true
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        min(heightLimit, linesView.contentHeight) + 2 * Self.padding
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 0, dy: Self.padding)
        linesView.frame = NSRect(x: 0, y: 0, width: max(linesView.contentWidth, scrollView.frame.width), height: linesView.contentHeight)
    }
}
