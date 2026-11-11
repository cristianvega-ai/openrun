import AppKit

/// The soft shadow that a pane casts on the pane at its left, so the panes
/// lie like stacked sheets (decision of 2026-10-26). The shadow lies over
/// the left pane and takes no clicks, so the edge of the pane stays easy to
/// drag.
@MainActor
final class SheetShadowView: NSView {
    static let width: CGFloat = 10
    private let gradient = CAGradientLayer()
    /// The opacity of the shadow at the edge of the pane that casts it.
    private(set) var edgeOpacity: CGFloat = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        wantsLayer = true
        (gradient.startPoint, gradient.endPoint) = (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        layer?.addSublayer(gradient)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("SheetShadowView does not come from a storyboard.")
    }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    /// A dark window needs a stronger shadow for the same depth.
    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        edgeOpacity = isDark ? 0.28 : 0.07
        gradient.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(edgeOpacity).cgColor]
        gradient.locations = [0, 1]
    }
}
