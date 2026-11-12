import AppKit
import PaneAppearance

/// A thin bar that shows the used part of one window of a usage limit.
@MainActor
final class UsageMeterView: NSView {
    static let height: CGFloat = 4
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    /// A window at its limit takes the attention color.
    var isAtLimit = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    /// The part of the width that the fill takes. A small use still shows.
    var filledWidth: CGFloat {
        let share = min(max(fraction, 0), 1)
        return share == 0 ? 0 : max(bounds.height, bounds.width * share)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        PaneColor.divider.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        (isAtLimit ? PaneColor.attention : PaneColor.quietText).setFill()
        let fill = NSRect(x: bounds.minX, y: bounds.minY, width: filledWidth, height: bounds.height)
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
