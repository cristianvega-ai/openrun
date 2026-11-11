import AppKit

/// A row of a list in a pane. The selection is a soft rounded rectangle in
/// the theme's selection color, as in Bear, and quieter when the window is
/// not key. The text keeps its colors on it, because the theme has no
/// accent color.
@MainActor
public final class SelectedRowView: NSTableRowView {
    /// The space between the selection and the edges of the pane.
    static let inset = NSSize(width: 8, height: 1)
    static let cornerRadius: CGFloat = 6

    /// The table marks a row as emphasized only while it has the keyboard
    /// focus. Bear keeps a strong selection in the whole key window.
    public override var isEmphasized: Bool {
        get { window?.isKeyWindow ?? false }
        set { needsDisplay = true }
    }

    public override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    /// The color of the selection for the key state of the window.
    static func selectionColor(windowIsKey: Bool) -> NSColor {
        windowIsKey ? PaneColor.rowSelection : PaneColor.inactiveRowSelection
    }

    public override func drawSelection(in dirtyRect: NSRect) {
        let shape = bounds.insetBy(dx: Self.inset.width, dy: Self.inset.height)
        Self.selectionColor(windowIsKey: isEmphasized).setFill()
        NSBezierPath(roundedRect: shape, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyStateChanged), name: name, object: window)
        }
    }

    @objc private func keyStateChanged() {
        needsDisplay = true
    }
}
