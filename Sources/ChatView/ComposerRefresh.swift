import AppKit

/// How the composer shows the facts of the thread and its own state.
extension ComposerView {
    func show(_ facts: ChatThreadFacts, palette newPalette: ChatPalette) {
        palette = newPalette
        agentName = facts.agentName
        box.fillColor = newPalette.userMessageBackground
        box.borderColor = newPalette.divider
        textView.font = newPalette.bodyFont
        textView.textColor = newPalette.text
        textView.insertionPointColor = newPalette.text
        textView.placeholder = "Message \(facts.agentName)"
        textView.placeholderColor = newPalette.secondaryText
        footer.show(facts, palette: newPalette)
        refresh()
    }

    /// Shows the send control, the note and the previews as they are now.
    /// While the agent works, the send control stops the turn.
    func refresh() {
        let symbol = logic.isBusy ? "stop.circle" : "arrow.up.circle"
        sendButton.image = RowSymbol.image(symbol, pointSize: 20)
        sendButton.setAccessibilityLabel(logic.isBusy ? "Stop" : "Send")
        sendButton.toolTip = logic.isBusy ? "Stop (Command-Period)" : "Send (Return)"
        let canSend = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
        sendButton.contentTintColor = logic.isBusy || canSend ? palette.text : palette.secondaryText.withAlphaComponent(0.5)
        heldView.isHidden = logic.heldMessage == nil
        if let held = logic.heldMessage { heldView.show(held, agentName: agentName, palette: palette) }
        noteButton.isHidden = problem == nil
        noteButton.attributedTitle = NSAttributedString(string: problem ?? "", attributes: [
            .font: palette.smallFont, .foregroundColor: palette.secondaryText,
        ])
        previews.show(images, palette: palette)
        needsLayout = true
        heightChanged?()
    }
}
