import AppKit

/// A scroll view inside a row, such as a long output, that is bounded in
/// height and scrolls up and down. At its top and its bottom a scroll goes
/// on to the transcript, so the chat never gets stuck in a box.
final class InnerScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        contentView.drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether a scroll goes on to the transcript: a sideways scroll in a
    /// box as wide as its content, a box whose content fits, or a scroll
    /// past the top or the bottom.
    /// - Parameters:
    ///   - deltaY: More than zero moves toward the top.
    ///   - offset: The top of the visible content.
    ///   - maximumOffset: The largest offset.
    ///   - maximumOffsetX: The largest sideways offset.
    static func handsOn(deltaX: CGFloat, deltaY: CGFloat, offset: CGFloat, maximumOffset: CGFloat, maximumOffsetX: CGFloat = 0) -> Bool {
        if abs(deltaX) > abs(deltaY) { return maximumOffsetX <= 0 }
        if maximumOffset <= 0 { return true }
        if deltaY > 0 { return offset <= 0 }
        if deltaY < 0 { return offset >= maximumOffset }
        return false
    }

    override func scrollWheel(with event: NSEvent) {
        let maximum = (documentView?.frame.height ?? 0) - contentView.bounds.height
        let maximumX = hasHorizontalScroller ? (documentView?.frame.width ?? 0) - contentView.bounds.width : 0
        if Self.handsOn(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, offset: contentView.bounds.minY,
                        maximumOffset: maximum, maximumOffsetX: maximumX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
