import AppKit

/// A quiet box of monospaced text under an open line, such as the input
/// and the output of a tool call. A long text wraps and scrolls inside a
/// box of bounded height, so all of it can be read.
final class DetailBoxView: RoundedBoxView, MeasurableView {
    static let padding = NSSize(width: 12, height: 8)
    static let maximumHeight: CGFloat = 300
    let scrollView = InnerScrollView()
    let textView = ChatTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 6
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        addSubview(scrollView)
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
        min(Self.maximumHeight, textView.fittingHeight(forWidth: width - 2 * Self.padding.width)) + 2 * Self.padding.height
    }

    override func layout() {
        super.layout()
        // The scroll view reaches the edges of the box, so its scroller
        // sits at the edge, and the inset of the text keeps its margins.
        scrollView.frame = bounds.insetBy(dx: 0, dy: Self.padding.height)
        textView.textContainerInset = NSSize(width: Self.padding.width, height: 0)
        let height = textView.fittingHeight(forWidth: bounds.width - 2 * Self.padding.width)
        textView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
    }
}
