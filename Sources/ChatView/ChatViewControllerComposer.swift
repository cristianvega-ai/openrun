import AppKit

/// The composer of the chat and its place under the transcript.
extension ChatViewController {
    /// The view that takes the keyboard focus when the pane opens.
    public var focusView: NSView { composer.textView }

    func connectComposer() {
        composer.textView.string = ComposerDrafts.draft(for: facts.threadIdentifier)
        composer.show(facts, palette: context.palette)
        composer.sendAction = { [weak self] message in
            guard let self else { return }
            scrollView.scrollToNewest()
            delegate?.chatViewController(self, send: message)
        }
        composer.stopAction = { [weak self] in
            guard let self else { return }
            delegate?.chatViewControllerStop(self)
        }
        composer.footer.modelButton.selectAction = { [weak self] choice in
            guard let self else { return }
            delegate?.chatViewController(self, selectModel: choice.identifier)
        }
        composer.footer.modeButton.selectAction = { [weak self] choice in
            guard let self else { return }
            delegate?.chatViewController(self, selectPermissionMode: choice.identifier)
        }
        composer.heightChanged = { [weak self] in self?.viewIfLoaded?.needsLayout = true }
        // The draft is saved at each edit, because a host can close the
        // chat of a thread at any time.
        composer.textChanged = { [weak self] text in
            guard let self else { return }
            ComposerDrafts.save(text, for: facts.threadIdentifier)
        }
    }

    /// Keeps the draft of the thread that the chat leaves, and shows the
    /// draft of the new one.
    func switchDraft(from oldThread: String) {
        ComposerDrafts.save(composer.textView.string, for: oldThread)
        composer.textView.string = ComposerDrafts.draft(for: facts.threadIdentifier)
    }

    func layoutChat() {
        let bounds = view.bounds
        let composerHeight = composer.height(forWidth: bounds.width)
        composer.frame = NSRect(x: 0, y: bounds.height - composerHeight, width: bounds.width, height: composerHeight)
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - composerHeight)
    }
}
