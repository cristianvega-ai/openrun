import AppKit
import TerminalEmulation

/// A scroll bar in the overlay style of macOS. Its knob shows where the visible rows are in the
/// scrollback, and the bar is hidden when there is no scrollback. AppKit draws the overlay knob
/// only for an `NSScrollView`, so the bar is one with a document of fake size: the height of all rows.
@MainActor
final class OverlayScrollBar: NSView {
    /// A document view that counts from the top, as the rows do.
    private final class TopDownView: NSView {
        override var isFlipped: Bool { true }
    }

    let scrollView = NSScrollView()
    /// What the knob shows now. Each frame calls `update`, and most of the time nothing changes.
    private var last: (scrollbar: Scrollbar, height: CGFloat)?

    var scroller: NSScroller { scrollView.verticalScroller! }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay), height: 100))
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = TopDownView()
        addSubview(scrollView)
    }

    /// A bar that is not shown must not take the clicks and the wheel of the grid below it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    required init?(coder: NSCoder) {
        fatalError("OverlayScrollBar does not come from a storyboard.")
    }

    /// Moves the knob to the place of the visible rows.
    func update(from scrollbar: Scrollbar) {
        isHidden = scrollbar.totalRows <= scrollbar.visibleRows
        guard !isHidden, let document = scrollView.documentView, last?.scrollbar != scrollbar || last?.height != bounds.height else { return }
        last = (scrollbar, bounds.height)
        // A visible row has the height of the bar divided by the number of visible rows.
        let rowHeight = bounds.height / CGFloat(scrollbar.visibleRows)
        document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: rowHeight * CGFloat(scrollbar.totalRows))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: rowHeight * CGFloat(scrollbar.firstVisibleRow)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
