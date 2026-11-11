import AgentConversation
import AppKit

/// A message of the user: plain text in a quiet bubble at the right of the
/// column, so it is clearly the user's. Until the agent takes it, it shows
/// fainter.
final class UserMessageRowView: TranscriptRowView {
    static let padding = NSSize(width: 14, height: 9)
    let bubble = RoundedBoxView()
    let textView = ChatTextView()
    private var bubbleWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        bubble.cornerRadius = 14
        addSubview(bubble)
        bubble.addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        guard case .userMessage(let message)? = row.items.first.flatMap(context.item) else { return }
        let palette = context.palette
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = palette.markdownStyle.lineHeightMultiple
        var text = message.text
        if message.imageCount > 0 {
            let images = message.imageCount == 1 ? "1 image" : "\(message.imageCount) images"
            text = text.isEmpty ? images : text + "\n" + images
        }
        textView.show(NSAttributedString(string: text, attributes: [
            .font: palette.bodyFont, .foregroundColor: palette.text, .paragraphStyle: paragraph,
        ]))
        textView.selectedTextAttributes = [.backgroundColor: palette.selection]
        bubble.fillColor = palette.userMessageBackground
        bubble.alphaValue = message.isAccepted ? 1 : 0.6
    }

    override var searchableTextView: NSTextView? { textView }

    override func height(forWidth width: CGFloat) -> CGFloat {
        let maximum = (ChatColumn.frame(inWidth: width).width * 0.8).rounded() - 2 * Self.padding.width
        let height = textView.fittingHeight(forWidth: maximum)
        bubbleWidth = textView.usedWidth + 2 * Self.padding.width
        return height + 2 * Self.padding.height
    }

    override func layout() {
        super.layout()
        let column = ChatColumn.frame(inWidth: bounds.width)
        if bubbleWidth == 0 { _ = height(forWidth: bounds.width) }
        bubble.frame = NSRect(x: column.x + column.width - bubbleWidth, y: 0, width: bubbleWidth, height: bounds.height)
        textView.frame = bubble.bounds.insetBy(dx: Self.padding.width, dy: Self.padding.height)
    }
}
