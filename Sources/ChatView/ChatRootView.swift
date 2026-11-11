import AppKit

/// The view of the chat: it paints the background of the theme, so the chat
/// and a terminal beside it look like one surface.
final class ChatRootView: NSView {
    var palette: ChatPalette {
        didSet { needsDisplay = true }
    }

    init(palette: ChatPalette) {
        self.palette = palette
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        dirtyRect.fill()
    }
}
