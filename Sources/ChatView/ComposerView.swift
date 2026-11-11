import AgentConversation
import AppKit

/// The composer under the transcript: a field that grows up to a limit and
/// then scrolls, the images of the next message, the send control, a note,
/// and the line of facts under it.
final class ComposerView: NSView {
    let box = RoundedBoxView()
    let scrollView = NSScrollView()
    let textView = ComposerTextView()
    let previews = ImagePreviewsView()
    let sendButton = RowSymbol.button("arrow.up.circle", label: "Send", target: nil, action: nil)
    let noteButton = NSButton(title: "", target: nil, action: nil)
    let footer = ComposerFooterView()
    var logic = ComposerLogic()
    var images: [MessageImage] = []
    /// A message about an image that could not go, until the next edit.
    var problem: String?
    var palette: ChatPalette
    var agentName = "the agent"
    var sendAction: ((ChatOutgoingMessage) -> Void)?
    var stopAction: (() -> Void)?
    /// Gives the text of the field after each change.
    var textChanged: ((String) -> Void)?
    /// Tells the controller to lay out again when the height changes.
    var heightChanged: (() -> Void)?

    init(palette: ChatPalette) {
        self.palette = palette
        super.init(frame: .zero)
        box.cornerRadius = 14
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
        noteButton.isBordered = false
        noteButton.alignment = .left
        for view in [previews, scrollView, sendButton] as [NSView] { box.addSubview(view) }
        for view in [noteButton, box, footer] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// The places of the parts at a width, with the text as it is now.
    func composerLayout(forWidth width: CGFloat) -> ComposerLayout {
        let font = palette.bodyFont
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        var textHeight = lineHeight
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            container.containerSize = NSSize(width: ComposerLayout.fieldWidth(forWidth: width), height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            textHeight = ceil(layoutManager.usedRect(for: container).height)
        }
        return ComposerLayout(width: width, textHeight: textHeight, lineHeight: lineHeight, hasNote: !noteButton.isHidden, hasImages: !images.isEmpty)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        composerLayout(forWidth: width).height
    }

    override func layout() {
        super.layout()
        let layout = composerLayout(forWidth: bounds.width)
        noteButton.frame = layout.note ?? .zero
        box.frame = layout.box
        previews.isHidden = layout.previews == nil
        previews.frame = layout.previews ?? .zero
        scrollView.frame = layout.field
        sendButton.frame = layout.button
        footer.frame = layout.footer
    }
}
