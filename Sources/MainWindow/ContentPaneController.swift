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
        self.content?.topRowItems.forEach { $0.removeFromSuperview() }
        self.content = content
        emptyLabel.isHidden = content != nil
        titleLabel.stringValue = content?.title ?? ""
        if let content {
            content.view.translatesAutoresizingMaskIntoConstraints = false
            contentArea.addSubview(content.view)
            NSLayoutConstraint.activate(Self.fill(content.view, below: nil, in: contentArea))
            content.topRowItems.forEach(topRow.trailingItems.addArrangedSubview)
        }
        minimumSizeChanged?()
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
