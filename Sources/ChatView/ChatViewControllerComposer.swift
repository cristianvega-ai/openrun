import AppKit

/// The composer of the chat and its place under the transcript.
extension ChatViewController {
    /// The view that takes the keyboard focus when the pane opens.
    public var focusView: NSView { composer.textView }

    func connectComposer() {
        composer.draft = ComposerDrafts.shared.draft(for: facts.threadIdentifier)
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
        composer.draftChanged = { [weak self] draft in
            guard let self else { return }
            ComposerDrafts.shared.save(draft, for: facts.threadIdentifier)
        }
    }

    /// Forgets the unsent text and images of a thread. The host calls it
    /// when the thread closes, because a draft otherwise stays while the
    /// app runs.
    public static func forgetDraft(ofThread identifier: String) {
        ComposerDrafts.shared.forget(identifier)
    }

    /// Puts text into the composer of a thread whose chat is not open
    /// yet, such as a new thread that goes on with an earlier one.
    public static func setDraft(_ text: String, ofThread identifier: String) {
        ComposerDrafts.shared.save(ComposerDrafts.Draft(text: text), for: identifier)
    }

    /// Keeps the draft of the thread that the chat leaves, and shows the
    /// draft of the new one.
    func switchDraft(from oldThread: String) {
        ComposerDrafts.shared.save(composer.draft, for: oldThread)
        composer.draft = ComposerDrafts.shared.draft(for: facts.threadIdentifier)
    }

    /// The room that a waiting request needs: its heading, four lines of
    /// its text and its buttons.
    static let minimumTranscriptHeight: CGFloat = 340

    func layoutChat() {
        let bounds = view.bounds
        // The field gives way first, so the transcript keeps room for a
        // request that waits. At the minimum size the field has one line.
        composer.fieldHeightLimit = 0
        let oneLine = composer.height(forWidth: bounds.width)
        composer.fieldHeightLimit = min(ComposerLayout.maximumFieldHeight, bounds.height - Self.minimumTranscriptHeight - oneLine)
        let composerHeight = composer.isHidden ? 12 : max(oneLine, composer.height(forWidth: bounds.width))
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
        if context.viewportHeight != scrollView.frame.height {
            // A request that waits fits its boxes to the transcript.
            context.viewportHeight = scrollView.frame.height
            let requests = transcriptView.rows.filter { if case .permissionRequest = $0.kind { true } else { false } }
            if !requests.isEmpty { transcriptView.setRows(transcriptView.rows, changed: Set(requests.map(\.key))) }
        }
        emptyView.frame = scrollView.frame
        let side = JumpToNewestButton.side
        jumpButton.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: bottom - side - 12, width: side, height: side)
    }
}
