import AppKit

/// The background of a pane in one color of the theme. Each pane is a sheet
/// of its own color, so the window reads as one themed surface.
@MainActor
public final class PaneBackgroundView: NSView {
    private let color: NSColor

    public init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("PaneBackgroundView does not come from a storyboard.")
    }

    public override var isOpaque: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.intersection(bounds).fill()
    }
}
