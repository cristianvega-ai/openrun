import AppKit

/// The soft shadow that a pane casts on the pane at its left, so the panes
/// lie like stacked sheets (decision of 2026-10-26). The shadow lies over
/// the left pane and takes no clicks, so the edge of the pane stays easy to
/// drag.
@MainActor
final class SheetShadowView: NSView {
    static let width: CGFloat = 14
    /// The share of the edge opacity at each stop. The shadow grows slowly
    /// and then fast near the edge, as a real shadow does, so it has no hard line.
    static let curve: [(location: CGFloat, share: CGFloat)] = [(0, 0), (0.5, 0.2), (0.8, 0.55), (1, 1)]
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

    /// A dark window needs a much stronger shadow for the same depth, because
    /// black on a dark pane changes it little.
    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        edgeOpacity = isDark ? 0.5 : 0.07
        gradient.colors = Self.curve.map { NSColor.black.withAlphaComponent(edgeOpacity * $0.share).cgColor }
        gradient.locations = Self.curve.map { NSNumber(value: Double($0.location)) }
    }

    /// The opacity of the shadow at a place from 0, its far side, to 1, the edge.
    func opacity(at location: CGFloat) -> CGFloat {
        guard let upper = Self.curve.firstIndex(where: { $0.location >= location }), upper > 0 else { return 0 }
        let (low, high) = (Self.curve[upper - 1], Self.curve[upper])
        let fraction = (location - low.location) / (high.location - low.location)
        return edgeOpacity * (low.share + (high.share - low.share) * fraction)
    }
}
