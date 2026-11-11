import AppKit

/// Find in the chat: Command-F shows the bar, and each match scrolls into
/// sight with its text selected.
extension ChatViewController {
    /// Takes the actions of the Find menu, such as Command-F and
    /// Command-G, from the responder chain.
    public override func performTextFinderAction(_ sender: Any?) {
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        switch NSTextFinder.Action(rawValue: tag) {
        case .nextMatch: moveFind(by: 1)
        case .previousMatch: moveFind(by: -1)
        case .hideFindInterface: hideFind()
        default: showFind()
        }
    }

    @objc public func performFindPanelAction(_ sender: Any?) {
        performTextFinderAction(sender)
    }

    public func showFind() {
        findBar.searchAction = { [weak self] query in self?.find(query) }
        findBar.moveAction = { [weak self] delta in self?.moveFind(by: delta) }
        findBar.doneAction = { [weak self] in self?.hideFind() }
        findBar.isHidden = false
        view.needsLayout = true
        view.window?.makeFirstResponder(findBar.field)
        find(findBar.field.stringValue)
    }

    func hideFind() {
        findBar.isHidden = true
        view.needsLayout = true
        view.window?.makeFirstResponder(focusView)
    }

    /// Finds the words, and shows the newest match, nearest to where the
    /// user usually reads.
    func find(_ query: String) {
        findMatches = TranscriptSearch.matches(of: query, in: transcriptView.rows, context: context)
        findIndex = findMatches.isEmpty ? nil : findMatches.count - 1
        showMatch()
    }

    func moveFind(by delta: Int) {
        guard let index = findIndex, !findMatches.isEmpty else { return }
        findIndex = (index + delta + findMatches.count) % findMatches.count
        showMatch()
    }

    private func showMatch() {
        findBar.show(matchIndex: findIndex, count: findMatches.count, palette: context.palette)
        guard let index = findIndex, let row = scrollView.reveal(findMatches[index].rowKey) else { return }
        guard let textView = row.searchableTextView, NSMaxRange(findMatches[index].range) <= textView.string.utf16.count else { return }
        textView.setSelectedRange(findMatches[index].range)
        textView.showFindIndicator(for: findMatches[index].range)
    }
}
