import AppKit
import PaneAppearance

/// The quiet moving mark of a row in progress: a short arc that turns. Core
/// Animation turns it in the render server, so it costs the app no
/// measurable processor time. With Reduce Motion the arc stands still.
@MainActor
final class ProgressMarkView: NSView {
    static let size: CGFloat = 10
    let arc = CAShapeLayer()
    /// The setting of Reduce Motion. Tests set it.
    var reducesMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        arc.path = CGPath(ellipseIn: CGRect(x: 1, y: 1, width: Self.size - 2, height: Self.size - 2), transform: nil)
        (arc.fillColor, arc.lineWidth, arc.lineCap, arc.strokeEnd) = (nil, 1.5, .round, 0.7)
        arc.frame = bounds
        layer?.addSublayer(arc)
        setAccessibilityElement(false)
        // NSWorkspace posts the change of Reduce Motion on its own center.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateMotion),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    }

    required init?(coder: NSCoder) {
        fatalError("ProgressMarkView does not come from a storyboard.")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.size, height: Self.size) }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            arc.strokeColor = PaneColor.quietText.cgColor
        }
    }

    var isTurning: Bool { arc.animation(forKey: "turn") != nil }

    /// The arc turns only while it is in a window and visible.
    @objc func updateMotion() {
        guard window != nil, !isHiddenOrHasHiddenAncestor, !reducesMotion() else {
            arc.removeAnimation(forKey: "turn")
            return
        }
        guard !isTurning else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        (turn.fromValue, turn.toValue, turn.duration, turn.repeatCount) = (0, -2 * Double.pi, 1.2, .infinity)
        arc.add(turn, forKey: "turn")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMotion()
    }

    override func viewDidHide() { super.viewDidHide(); updateMotion() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateMotion() }
}
