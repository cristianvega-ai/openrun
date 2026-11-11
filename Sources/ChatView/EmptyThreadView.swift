import AppKit

/// What an empty thread shows in place of the transcript: the agent's name
/// and a quiet line, in the middle of the pane.
final class EmptyThreadView: NSView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "Send a message to start the thread.")

    override init(frame: NSRect) {
        super.init(frame: frame)
        for label in [title, detail] {
            label.alignment = .center
            addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(agentName: String, palette: ChatPalette) {
        title.stringValue = agentName
        title.font = NSFont.systemFont(ofSize: palette.bodyFont.pointSize + 6, weight: .semibold)
        title.textColor = palette.text
        detail.font = palette.bodyFont
        detail.textColor = palette.secondaryText
    }

    override func layout() {
        super.layout()
        let middle = (bounds.height / 2).rounded()
        title.frame = NSRect(x: 0, y: middle + 2, width: bounds.width, height: 26)
        detail.frame = NSRect(x: 0, y: middle - 24, width: bounds.width, height: 20)
    }
}
