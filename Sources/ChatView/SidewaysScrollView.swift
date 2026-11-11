import AppKit

/// A scroll view that scrolls only sideways, such as the box of a code
/// block. A mostly vertical scroll goes on to the transcript, so the chat
/// scrolls past the box without a stop.
final class SidewaysScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .none
        contentView.drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
