import AppKit

/// The field of the composer. Return sends, and Shift-Return or
/// Option-Return starts a new line. While an input method marks text, Return
/// goes to the input method, so a word is never sent half done.
final class ComposerTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var placeholderColor = NSColor.placeholderTextColor
    var sendAction: (() -> Void)?
    /// Escape, or Command-Period with `isImmediate` set.
    var stopAction: ((_ isImmediate: Bool) -> Void)?
    /// Pasted or dropped images. A dropped file that is no image gives
    /// its path as text instead.
    var imagesAction: (([Data]) -> Void)?

    /// The field uses TextKit 1, as the rows do, to measure its text.
    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        isRichText = false
        allowsUndo = true
        drawsBackground = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isVerticallyResizable = true
        autoresizingMask = [.width]
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func doCommand(by selector: Selector) {
        let modifiers = NSApp?.currentEvent?.modifierFlags ?? []
        switch selector {
        case #selector(insertNewline(_:)) where !hasMarkedText():
            if modifiers.contains(.shift) || modifiers.contains(.option) { insertNewlineIgnoringFieldEditor(nil) } else { sendAction?() }
        // Tab moves the focus, as in a form. Option-Tab types a tab.
        case #selector(insertTab(_:)): window?.selectNextKeyView(self)
        case #selector(insertBacktab(_:)): window?.selectPreviousKeyView(self)
        case #selector(cancelOperation(_:)) where !hasMarkedText():
            stopAction?(modifiers.contains(.command))
        default:
            super.doCommand(by: selector)
        }
    }

    override func paste(_ sender: Any?) {
        let images = Self.imageData(on: .general)
        guard images.isEmpty else { return imagesAction?(images) ?? () }
        pasteAsPlainText(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            let images = Self.imageData(on: board)
            if !images.isEmpty { imagesAction?(images) }
            return images.isEmpty ? super.performDragOperation(sender) : true
        }
        var paths: [String] = []
        var images: [Data] = []
        for url in urls {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe), ComposerImage.mediaType(of: data) != nil {
                images.append(data)
            } else {
                paths.append(url.path)
            }
        }
        if !images.isEmpty { imagesAction?(images) }
        if !paths.isEmpty { insertText(paths.map(DroppedPath.text).joined(separator: " ") + " ", replacementRange: selectedRange()) }
        return true
    }

    /// The image data on a pasteboard: an image that was copied, or the
    /// files of images.
    static func imageData(on board: NSPasteboard) -> [Data] {
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let files = urls.compactMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }.filter { ComposerImage.mediaType(of: $0) != nil }
        if !files.isEmpty { return files }
        for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType("public.jpeg"), .tiff] {
            guard let data = board.data(forType: type) else { continue }
            if type == .tiff { return NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]).map { [$0] } ?? [] }
            return [data]
        }
        return []
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), let font else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        placeholder.draw(at: origin, withAttributes: [.font: font, .foregroundColor: placeholderColor])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
