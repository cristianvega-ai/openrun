import AppKit
import TerminalView

/// The view of one session pane. The terminal view fills it once the attach
/// brings the snapshot, and the label of the hidden part of the grid lies
/// over its bottom right corner.
@MainActor
public final class SessionPaneView: NSView {
    let hiddenGridLabel = HiddenGridLabel()
    private(set) var terminalView: TerminalView?
    /// The controller shows a failure that waited for a window.
    var windowChanged: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        hiddenGridLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hiddenGridLabel)
        hiddenGridLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16).isActive = true
        hiddenGridLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("SessionPaneView does not come from a storyboard.")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged?()
    }

    /// A host can give the pane the keyboard focus before the attach ends.
    /// The terminal view takes it over when it comes.
    public override var acceptsFirstResponder: Bool { terminalView == nil }

    /// Shows the terminal view, and gives it the keyboard focus when the
    /// pane had it or nothing in the window had it.
    func show(_ terminalView: TerminalView) {
        self.terminalView = terminalView
        terminalView.frame = bounds
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView, positioned: .below, relativeTo: hiddenGridLabel)
        if let window, window.firstResponder === self || window.firstResponder === window {
            window.makeFirstResponder(terminalView)
        }
    }
}
