import AppKit
import PaneAppearance

/// The dot of a row that needs the user. It has the box of the progress arc
/// and touches the trailing side of that box, so the two marks and the age
/// end at one edge.
@MainActor
final class AttentionMarkView: NSView {
    static let diameter: CGFloat = 8

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: ProgressMarkView.size, height: ProgressMarkView.size))
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("AttentionMarkView does not come from a storyboard.")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: ProgressMarkView.size, height: ProgressMarkView.size) }

    override func draw(_ dirtyRect: NSRect) {
        PaneColor.attention.setFill()
        let inset = (bounds.height - Self.diameter) / 2
        NSBezierPath(ovalIn: NSRect(x: bounds.maxX - Self.diameter, y: inset, width: Self.diameter, height: Self.diameter)).fill()
    }
}
