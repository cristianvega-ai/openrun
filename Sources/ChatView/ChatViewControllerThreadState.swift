import AppKit

/// The top row of the pane and the state of the thread around the
/// transcript.
extension ChatViewController {
    /// The controls for the top row of the pane, from left to right: the
    /// agent and the account, and a button that opens the conversation in
    /// a terminal. The same views stay up to date.
    public var topRowItems: [NSView] { [agentLabel, terminalButton] }

    @objc func openInTerminal() {
        delegate?.chatViewControllerOpenInTerminal(self)
    }

    /// Shows the condition of the thread, the empty thread, and the
    /// composer only while the thread is not open in a terminal.
    func showThreadState() {
        let words = ThreadConditionWords(facts)
        conditionView.isHidden = words == nil
        if let words { conditionView.show(words, palette: context.palette) }
        composer.isHidden = facts.condition == .openInTerminal
        emptyView.isHidden = !transcript.items.isEmpty || facts.condition != .ready
        emptyView.show(agentName: facts.agentName, palette: context.palette)
        jumpButton.show(palette: context.palette)
        agentLabel.stringValue = [facts.agentName, facts.accountName].compactMap { $0 }.joined(separator: " · ")
        agentLabel.font = context.palette.smallFont
        agentLabel.textColor = context.palette.secondaryText
        terminalButton.isBordered = false
        terminalButton.image = RowSymbol.image("terminal", pointSize: 12)
        terminalButton.imagePosition = .imageLeading
        terminalButton.contentTintColor = context.palette.secondaryText
        terminalButton.isHidden = facts.condition == .openInTerminal
        viewIfLoaded?.needsLayout = true
    }
}
