import AppKit
import MarkdownText

/// A code block of an agent's message in a box of its own. Long lines
/// scroll sideways instead of wrapping, and a button copies the code.
final class CodeBlockRowView: TranscriptRowView {
    static let headerHeight: CGFloat = 30
    static let padding: CGFloat = 12
    let box = RoundedBoxView()
    let language = NSTextField(labelWithString: "")
    lazy var copyButton = RowSymbol.button("doc.on.doc", label: "Copy Code", target: self, action: #selector(copyCode))
    let scrollView = SidewaysScrollView()
    let textView = ChatTextView()
    private(set) var code = ""
    /// The general pasteboard, or a private one in tests.
    var pasteboard = NSPasteboard.general
    private var indentation: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        box.cornerRadius = 8
        addSubview(box)
        for view in [language, copyButton, scrollView] as [NSView] { box.addSubview(view) }
        textView.textContainer?.widthTracksTextView = false
        textView.isHorizontallyResizable = true
        scrollView.documentView = textView
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        guard case .agentCode(let item, let index) = row.kind, let blocks = context.documents[item]?.blocks,
            let block = blocks.indices.contains(index) ? blocks[index] : nil,
            case .code(let name, let text, _) = block.kind else { return }
        let palette = context.palette
        code = text
        indentation = CGFloat(block.listDepth) * context.renderer.indentation
        box.fillColor = palette.codeBackground
        box.borderColor = palette.divider
        language.stringValue = name ?? ""
        language.font = palette.smallFont
        language.textColor = palette.secondaryText
        copyButton.contentTintColor = palette.secondaryText
        textView.selectedTextAttributes = [.backgroundColor: palette.selection]
        textView.show(context.renderer.codeAttributedString(text))
        setAccessibilityLabel(name.map { "Code in \($0)" } ?? "Code")
    }

    override var searchableTextView: NSTextView? { textView }

    override func height(forWidth width: CGFloat) -> CGFloat {
        textView.fittingHeight(forWidth: .greatestFiniteMagnitude) + Self.headerHeight + Self.padding
    }

    override func layout() {
        super.layout()
        let column = ChatColumn.frame(inWidth: bounds.width)
        box.frame = NSRect(x: column.x + indentation, y: 0, width: column.width - indentation, height: bounds.height)
        let header = Self.headerHeight
        language.frame = NSRect(x: Self.padding, y: (header - 16) / 2, width: box.bounds.width / 2, height: 16)
        copyButton.frame = NSRect(x: box.bounds.width - header - 2, y: 0, width: header, height: header)
        scrollView.frame = NSRect(x: Self.padding, y: header, width: box.bounds.width - 2 * Self.padding, height: box.bounds.height - header - Self.padding)
        textView.frame = NSRect(x: 0, y: 0, width: max(textView.usedWidth + 4, scrollView.frame.width), height: scrollView.frame.height)
    }

    @objc func copyCode() {
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        copyButton.image = RowSymbol.image("checkmark", pointSize: 12)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.image = RowSymbol.image("doc.on.doc", pointSize: 12)
        }
    }
}
