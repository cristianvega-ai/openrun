import AppKit

/// What the composer does when the user sends or stops, and when a turn
/// starts or ends.
extension ComposerView: NSTextViewDelegate {
    func connectSending() {
        textView.delegate = self
        sendButton.target = self
        sendButton.action = #selector(sendOrStop)
        textView.sendAction = { [weak self] in self?.submit() }
        textView.stopAction = { [weak self] isImmediate in
            guard let self else { return }
            if isImmediate || logic.escape(isFieldEmpty: textView.string.isEmpty) == .stop { stopAction?() }
        }
    }

    /// The transcript tells whether the agent works. A held message goes
    /// when the turn ends.
    func setBusy(_ isBusy: Bool) {
        if case .send(let message) = logic.setBusy(isBusy) { sendAction?(message) }
        refresh()
    }

    func submit() {
        let message = ChatOutgoingMessage(text: textView.string, images: images)
        let effect = logic.submit(message)
        if case .send(let outgoing) = effect { sendAction?(outgoing) }
        if effect != .none || logic.heldMessage != nil, !message.text.isEmpty || !images.isEmpty {
            textView.string = ""
            images = []
            textChanged?("")
        }
        refresh()
    }

    @objc func sendOrStop() {
        if logic.isBusy { stopAction?() } else { submit() }
    }

    func textDidChange(_ notification: Notification) {
        problem = nil
        textChanged?(textView.string)
        refresh()
    }
}
