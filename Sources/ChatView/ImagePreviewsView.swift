import AgentConversation
import AppKit

/// The images that go with the next message, as small previews. Each one
/// has a button that removes it.
final class ImagePreviewsView: NSView {
    static let height: CGFloat = 60
    static let side: CGFloat = 52
    var removeAction: ((Int) -> Void)?
    private(set) var previews: [NSImageView] = []
    private var removeButtons: [NSButton] = []

    override var isFlipped: Bool { true }

    func show(_ images: [MessageImage], palette: ChatPalette) {
        subviews.forEach { $0.removeFromSuperview() }
        previews = images.enumerated().map { index, image in
            let view = NSImageView(image: NSImage(data: image.data) ?? NSImage())
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            view.layer?.cornerRadius = 6
            view.layer?.masksToBounds = true
            view.setAccessibilityLabel("Image \(index + 1)")
            return view
        }
        removeButtons = images.indices.map { index in
            let button = RowSymbol.button("xmark.circle", label: "Remove Image \(index + 1)", target: self, action: #selector(remove(_:)))
            button.tag = index
            button.contentTintColor = palette.secondaryText
            return button
        }
        for (preview, button) in zip(previews, removeButtons) {
            addSubview(preview)
            addSubview(button)
        }
        needsLayout = true
    }

    @objc func remove(_ sender: NSButton) {
        removeAction?(sender.tag)
    }

    override func layout() {
        super.layout()
        for (index, (preview, button)) in zip(previews, removeButtons).enumerated() {
            let x = CGFloat(index) * (Self.side + 10)
            preview.frame = NSRect(x: x, y: Self.height - Self.side, width: Self.side, height: Self.side)
            button.frame = NSRect(x: preview.frame.maxX - 12, y: 0, width: 18, height: 18)
        }
    }
}
