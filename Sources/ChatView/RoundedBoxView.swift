import AppKit

/// A rounded box with a fill and an optional border, such as the bubble of
/// a user message or the box of code.
///
/// It draws its colors itself, so a dynamic color follows a change of the
/// appearance with no extra step.
class RoundedBoxView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var borderColor: NSColor? { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 1 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 8 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let inset = borderColor == nil ? 0 : borderWidth / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        if let borderColor {
            borderColor.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
    }
}
