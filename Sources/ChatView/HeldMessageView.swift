import AgentConversation
import AppKit

/// The message that waits above the composer while the agent works: its
/// text, quiet and at most three lines high, with controls to take it back
/// into the field to change it, or to delete it.
final class HeldMessageView: RoundedBoxView, MeasurableView {
    static let padding = NSSize(width: 12, height: 8)
    static let headerHeight: CGFloat = 18
    let label = NSTextField(labelWithString: "")
    let text = NSTextField(wrappingLabelWithString: "")
    lazy var editButton = Self.button("Edit", target: self, action: #selector(edit))
    lazy var deleteButton = Self.button("Delete", target: self, action: #selector(delete))
    var editAction: (() -> Void)?
    var deleteAction: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 10
        text.maximumNumberOfLines = 3
        text.lineBreakMode = .byTruncatingTail
        text.cell?.truncatesLastVisibleLine = true
        for view in [label, text, editButton, deleteButton] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        return button
    }

    func show(_ message: ChatOutgoingMessage, agentName: String, palette: ChatPalette) {
        fillColor = palette.codeBackground
        label.stringValue = "Sends when \(agentName) finishes"
        let images = message.images.count
        let imageText = images == 0 ? "" : images == 1 ? " (1 image)" : " (\(images) images)"
        text.stringValue = message.text + imageText
        for field in [label, text] { field.font = palette.smallFont }
        label.textColor = palette.secondaryText
        text.textColor = palette.text
        for button in [editButton, deleteButton] {
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: palette.smallFont, .foregroundColor: palette.secondaryText])
        }
        setAccessibilityLabel(label.stringValue + ": " + text.stringValue)
        needsLayout = true
    }

    @objc func edit() { editAction?() }
    @objc func delete() { deleteAction?() }

    private func textHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 2 * Self.padding.width, height: 1_000)).height ?? 0)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        Self.padding.height * 2 + Self.headerHeight + 2 + textHeight(forWidth: width)
    }

    override func layout() {
        super.layout()
        let pad = Self.padding
        let delete = ceil(deleteButton.attributedTitle.size().width) + 8
        let edit = ceil(editButton.attributedTitle.size().width) + 8
        deleteButton.frame = NSRect(x: bounds.width - pad.width - delete + 4, y: pad.height, width: delete, height: Self.headerHeight)
        editButton.frame = NSRect(x: deleteButton.frame.minX - edit, y: pad.height, width: edit, height: Self.headerHeight)
        label.frame = NSRect(x: pad.width, y: pad.height, width: max(0, editButton.frame.minX - pad.width - 8), height: Self.headerHeight)
        text.frame = NSRect(x: pad.width, y: pad.height + Self.headerHeight + 2, width: bounds.width - 2 * pad.width,
                            height: textHeight(forWidth: bounds.width))
    }
}
