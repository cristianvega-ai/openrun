import AppKit
import WindowLayout

/// The two halves of one split, with a divider that the user can move.
/// The first half keeps its share of the room when the view changes size.
@MainActor final class HalvesView: NSView {
    static let dividerWidth: CGFloat = 1
    /// The room around the divider that takes a drag.
    private static let grip: CGFloat = 4
    let split: LayoutSplit
    private(set) var fraction: CGFloat
    let first: NSView
    let second: NSView
    private let divider = NSView()
    var fractionChanged: ((Double) -> Void)?

    init(split: LayoutSplit, first: NSView, second: NSView) {
        (self.split, self.first, self.second, fraction) = (split, first, second, CGFloat(split.fraction))
        super.init(frame: .zero)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        for view in [first, second, divider] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    private var isSideBySide: Bool { split.direction == .sideBySide }
    private var length: CGFloat { (isSideBySide ? bounds.width : bounds.height) - Self.dividerWidth }

    override func layout() {
        super.layout()
        let firstLength = (max(0, length) * fraction).rounded()
        if isSideBySide {
            first.frame = NSRect(x: 0, y: 0, width: firstLength, height: bounds.height)
            divider.frame = NSRect(x: firstLength, y: 0, width: Self.dividerWidth, height: bounds.height)
            second.frame = NSRect(x: firstLength + Self.dividerWidth, y: 0, width: max(0, bounds.width - firstLength - Self.dividerWidth), height: bounds.height)
        } else {
            first.frame = NSRect(x: 0, y: 0, width: bounds.width, height: firstLength)
            divider.frame = NSRect(x: 0, y: firstLength, width: bounds.width, height: Self.dividerWidth)
            second.frame = NSRect(x: 0, y: firstLength + Self.dividerWidth, width: bounds.width, height: max(0, bounds.height - firstLength - Self.dividerWidth))
        }
    }

    /// The share of the first half, kept away from the two edges, so each half stays in view.
    func setFraction(_ new: CGFloat) {
        fraction = min(max(new, 0.1), 0.9)
        needsLayout = true
    }

    private func isOnDivider(_ point: NSPoint) -> Bool {
        divider.frame.insetBy(dx: isSideBySide ? -Self.grip : 0, dy: isSideBySide ? 0 : -Self.grip).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The halves take every click outside the room of the divider.
        let local = superview.map { convert(point, from: $0) } ?? point
        return isOnDivider(local) ? self : super.hitTest(point)
    }

    override func resetCursorRects() {
        let grip = divider.frame.insetBy(dx: isSideBySide ? -Self.grip : 0, dy: isSideBySide ? 0 : -Self.grip)
        addCursorRect(grip, cursor: isSideBySide ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard length > 0 else { return }
        setFraction((isSideBySide ? point.x : point.y) / length)
    }

    override func mouseUp(with event: NSEvent) {
        fractionChanged?(Double(fraction))
        window?.invalidateCursorRects(for: self)
    }
}
