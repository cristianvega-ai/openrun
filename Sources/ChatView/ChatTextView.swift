import AppKit

/// The text view of a row: selectable, not editable, with no background
/// and no inset, and with TextKit 1, which shows the tables of Markdown.
final class ChatTextView: NSTextView {
    /// Gets the target of a link that the user clicks. Nothing opens a
    /// link by itself.
    var linkAction: ((String) -> Void)?
    /// The whole message of the row, for Copy Message in the menu.
    var messageText: (() -> String)?
    /// The general pasteboard, or a private one in tests.
    var pasteboard = NSPasteboard.general

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        isAutomaticLinkDetectionEnabled = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    /// The height of the text when it wraps at `width`.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }

    /// The width of the longest line after a call of `fittingHeight`. The
    /// used rectangle of the container can span the full width, so this
    /// measures each line.
    var usedWidth: CGFloat {
        guard let layoutManager else { return 0 }
        var width: CGFloat = 0
        let glyphs = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in width = max(width, used.width) }
        return ceil(width)
    }

    /// Shows new text when it differs from the text that shows.
    func show(_ text: NSAttributedString) {
        guard let textStorage, !textStorage.isEqual(to: text) else { return }
        textStorage.setAttributedString(text)
    }
}

extension ChatTextView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at characterIndex: Int) -> Bool {
        let target = (link as? String) ?? (link as? URL)?.absoluteString
        if let target { linkAction?(target) }
        return true
    }

    /// Adds Copy Message at the top of the menu of a message.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at characterIndex: Int) -> NSMenu? {
        guard messageText != nil else { return menu }
        let item = NSMenuItem(title: "Copy Message", action: #selector(copyMessage), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc func copyMessage() {
        pasteboard.clearContents()
        pasteboard.setString(messageText?() ?? "", forType: .string)
    }
}
