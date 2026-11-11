import AppKit
import PaneAppearance

/// The third pane: a top row with the title and the controls of the
/// content, over the content or a quiet empty state.
@MainActor
public final class ContentPaneController {
    /// The minimum size of the pane while it shows no content.
    static let emptyMinimumSize = CGSize(width: 360, height: 240)
    public let view = PaneBackgroundView(color: PaneColor.terminalBackground)
    public let topRow = PaneTopRow(background: PaneColor.terminalBackground)
    /// The one place for the content. A split tree of several views takes
    /// this place later, so nothing else in the pane depends on one view.
    let contentArea = NSView()
    let titleLabel = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "No Session Selected")
    public private(set) var content: PaneContent?
    /// The constraint that gives the content the width of the pane, and the
    /// one that holds the width while the panes change their widths.
    private var contentTrailing, heldWidth: NSLayoutConstraint?
    private var resizeDepth = 0
    /// The window keeps room for the new minimum size.
    var minimumSizeChanged: (() -> Void)?

    init() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        (titleLabel.textColor, titleLabel.lineBreakMode) = (PaneColor.text, .byTruncatingMiddle)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (emptyLabel.font, emptyLabel.textColor) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.quietText)
        topRow.leadingItems.addArrangedSubview(titleLabel)
        for subview in [contentArea, topRow, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate(Self.fill(contentArea, below: topRow, in: view) + [
            topRow.topAnchor.constraint(equalTo: view.topAnchor),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: contentArea.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentArea.centerYAnchor),
        ])
    }

    var minimumSize: CGSize { content?.minimumSize ?? Self.emptyMinimumSize }

    /// Shows the content in place of the one before it, or the empty state.
    func show(_ content: PaneContent?) {
        self.content?.view.removeFromSuperview()
        (contentTrailing, heldWidth) = (nil, nil)
        self.content?.topRowItems.forEach { $0.removeFromSuperview() }
        self.content = content
        emptyLabel.isHidden = content != nil
        titleLabel.stringValue = content?.title ?? ""
        if let content {
            content.view.translatesAutoresizingMaskIntoConstraints = false
            contentArea.addSubview(content.view)
            let constraints = Self.fill(content.view, below: nil, in: contentArea)
            NSLayoutConstraint.activate(constraints)
            contentTrailing = constraints[2]
            if resizeDepth > 0 { holdWidth() }
            content.topRowItems.forEach(topRow.trailingItems.addArrangedSubview)
        }
        minimumSizeChanged?()
    }

    /// The panes start to change their widths in an animation or a drag. The content
    /// keeps its width until the end, so a session gets one size, not one for each step.
    func beginPaneResize() {
        resizeDepth += 1
        holdWidth()
    }

    /// The change ends. The content gets the final width in one layout.
    func endPaneResize() {
        resizeDepth = max(resizeDepth - 1, 0)
        guard resizeDepth == 0 else { return }
        heldWidth?.isActive = false
        contentTrailing?.isActive = true
        heldWidth = nil
    }

    private func holdWidth() {
        guard let view = content?.view, heldWidth == nil else { return }
        contentTrailing?.isActive = false
        heldWidth = view.widthAnchor.constraint(equalToConstant: contentArea.frame.width)
        heldWidth?.isActive = true
    }

    func updateTitle(_ title: String) {
        content?.title = title
        titleLabel.stringValue = title
    }

    func updateMinimumSize(_ size: CGSize) {
        content?.minimumSize = size
        minimumSizeChanged?()
    }

    private static func fill(_ subview: NSView, below top: NSView?, in container: NSView) -> [NSLayoutConstraint] {
        [subview.topAnchor.constraint(equalTo: top?.bottomAnchor ?? container.topAnchor),
         subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
         subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
         subview.bottomAnchor.constraint(equalTo: container.bottomAnchor)]
    }
}
