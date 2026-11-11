import AppKit

/// A run of blocks of an agent's message as rendered Markdown. The text
/// is selectable, and a click on a link goes to the host.
final class AgentTextRowView: TranscriptRowView {
    let textView = ChatTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        guard case .agentText(let item, let blocks) = row.kind else { return }
        textView.linkTextAttributes = [
            .foregroundColor: context.palette.link, .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.selectedTextAttributes = [.backgroundColor: context.palette.selection]
        textView.linkAction = { [weak context] target in context?.actions?.openLink(target) }
        textView.messageText = { [weak context] in context?.documents[item]?.text ?? "" }
        textView.show(context.text(ofBlocks: blocks, in: item))
    }

    override var searchableTextView: NSTextView? { textView }

    override func height(forWidth width: CGFloat) -> CGFloat {
        textView.fittingHeight(forWidth: ChatColumn.frame(inWidth: width).width)
    }

    override func layout() {
        super.layout()
        let column = ChatColumn.frame(inWidth: bounds.width)
        textView.frame = NSRect(x: column.x, y: 0, width: column.width, height: bounds.height)
    }
}
