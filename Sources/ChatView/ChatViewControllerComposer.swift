import AppKit

/// The composer of the chat and its place under the transcript.
extension ChatViewController {
    /// The view that takes the keyboard focus when the pane opens.
    public var focusView: NSView { composer.textView }

    func connectComposer() {
        composer.textView.string = ComposerDrafts.shared.draft(for: facts.threadIdentifier).text
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
        jumpButton.action = { [weak self] in self?.scrollView.scrollToNewest() }
        jumpButton.isHidden = true
        scrollView.followingChanged = { [weak self] isFollowing in self?.jumpButton.isHidden = isFollowing }
        conditionView.choiceAction = { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .returnFromTerminal: delegate?.chatViewControllerReturnFromTerminal(self)
            case .newThread(let account): delegate?.chatViewController(self, startNewThreadOnAccount: account)
            }
        }
        composer.heightChanged = { [weak self] in self?.viewIfLoaded?.needsLayout = true }
        // The draft is saved at each edit, because a host can close the
        // chat of a thread at any time.
        composer.textChanged = { [weak self] text in
            guard let self else { return }
            ComposerDrafts.shared.save(ComposerDrafts.Draft(text: text), for: facts.threadIdentifier)
        }
    }

    /// Keeps the draft of the thread that the chat leaves, and shows the
    /// draft of the new one.
    func switchDraft(from oldThread: String) {
        ComposerDrafts.shared.save(ComposerDrafts.Draft(text: composer.textView.string), for: oldThread)
        composer.textView.string = ComposerDrafts.shared.draft(for: facts.threadIdentifier).text
    }

    func layoutChat() {
        let bounds = view.bounds
        let composerHeight = composer.isHidden ? 12 : composer.height(forWidth: bounds.width)
        composer.frame = NSRect(x: 0, y: bounds.height - composerHeight, width: bounds.width, height: composerHeight)
        var bottom = composer.frame.minY
        if !conditionView.isHidden {
            let column = ChatColumn.frame(inWidth: bounds.width)
            let height = conditionView.height(forWidth: column.width)
            conditionView.frame = NSRect(x: column.x, y: bottom - height - 8, width: column.width, height: height)
            bottom = conditionView.frame.minY - 4
        }
        let top = findBar.isHidden ? 0 : FindBarView.height
        findBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: FindBarView.height)
        scrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: bottom - top)
        emptyView.frame = scrollView.frame
        let side = JumpToNewestButton.side
        jumpButton.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: bottom - side - 12, width: side, height: side)
    }
}
