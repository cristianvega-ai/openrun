import AppKit

/// A quiet box of monospaced text under an open line, such as the input
/// and the output of a tool call. A long text wraps and scrolls inside a
/// box of bounded height, so all of it can be read.
final class DetailBoxView: RoundedBoxView, MeasurableView {
    static let padding = NSSize(width: 12, height: 8)
    static let maximumHeight: CGFloat = 300
    /// The height of the text above which it scrolls.
    var heightLimit = DetailBoxView.maximumHeight
    let scrollView = InnerScrollView()
    let textView = ChatTextView()
    lazy var copyButton = RowSymbol.button("doc.on.doc", label: "Copy Output", target: self, action: #selector(copyAll))
    /// The text that the copy control copies. Nil hides the control.
    var copyText: String? {
        didSet {
            copyButton.isHidden = copyText == nil
            needsLayout = true
        }
    }
    /// The general pasteboard, or a private one in tests.
    var pasteboard = NSPasteboard.general

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 6
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        addSubview(scrollView)
        copyButton.isHidden = true
        addSubview(copyButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows parts of text with a quiet line between them. A part can end
    /// with a note in the font of prose, such as the count of hidden lines.
    func show(_ parts: [(text: String, note: String?)], palette: ChatPalette) {
        fillColor = palette.codeBackground
        let text = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        let code: [NSAttributedString.Key: Any] = [.font: palette.smallCodeFont, .foregroundColor: palette.text, .paragraphStyle: paragraph]
        let note: [NSAttributedString.Key: Any] = [.font: palette.smallFont, .foregroundColor: palette.secondaryText, .paragraphStyle: paragraph]
        for part in parts {
            if text.length > 0 { text.append(NSAttributedString(string: "\n", attributes: code)) }
            text.append(NSAttributedString(string: part.text, attributes: code))
            if let partNote = part.note { text.append(NSAttributedString(string: "\n" + partNote, attributes: note)) }
        }
        textView.selectedTextAttributes = [.backgroundColor: palette.selection]
        textView.show(text)
        needsLayout = true
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        min(heightLimit, textView.fittingHeight(forWidth: textWidth(inWidth: width))) + 2 * Self.padding.height
    }

    /// The text leaves room at the right for the copy control.
    private func textWidth(inWidth width: CGFloat) -> CGFloat {
        width - 2 * Self.padding.width - (copyText == nil ? 0 : 24)
    }

    override func layout() {
        super.layout()
        // The scroll view reaches the edges of the box, so its scroller
        // sits at the edge, and the inset of the text keeps its margins.
        scrollView.frame = bounds.insetBy(dx: 0, dy: Self.padding.height)
        textView.textContainerInset = NSSize(width: Self.padding.width, height: 0)
        let textWidth = textWidth(inWidth: bounds.width)
        let height = textView.fittingHeight(forWidth: textWidth)
        textView.frame = NSRect(x: 0, y: 0, width: textWidth + 2 * Self.padding.width, height: height)
        copyButton.frame = NSRect(x: bounds.width - 30, y: 2, width: 28, height: 26)
    }

    @objc func copyAll() {
        pasteboard.clearContents()
        pasteboard.setString(copyText ?? "", forType: .string)
    }
}
