import AppKit
import QuartzCore

/// Asks for a frame at the next step of the display, and then waits. A display
/// link steps in time with the screen, so a frame goes out once for each
/// refresh and never more. When no one asks, the link is paused and the view
/// uses no processor time.
@MainActor
final class DisplaySchedule: NSObject {
    private let view: NSView
    private let drawFrame: @MainActor () -> Void
    private var link: CADisplayLink?
    private var isRequested = false

    init(view: NSView, drawFrame: @escaping @MainActor () -> Void) {
        self.view = view
        self.drawFrame = drawFrame
    }

    /// Asks for one frame. A view without a window has no display, so the
    /// request waits until `viewDidMoveToWindow` calls `attach`.
    func requestFrame() {
        isRequested = true
        attach()
    }

    func attach() {
        guard isRequested, view.window != nil else { return }
        if link == nil {
            let newLink = view.displayLink(target: self, selector: #selector(step))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
        link?.isPaused = false
    }

    /// Ends the link. A link keeps its target alive until then.
    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        link.isPaused = true
        isRequested = false
        drawFrame()
    }
}
