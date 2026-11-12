import AppKit
import os
import TerminalEmulation

/// Find in the terminal (Command-F): the text of the screen and the
/// scrollback. The match that the user is at shows as the selection.
extension TerminalView {
    /// Takes the items of the Find menu, by their tags: Find, Find Next,
    /// Find Previous, and Use Selection for Find.
    @objc public func performFindPanelAction(_ sender: Any?) {
        switch NSFindPanelAction(rawValue: UInt((sender as? NSValidatedUserInterfaceItem)?.tag ?? 1)) {
        case .next: moveFind(older: true)
        case .previous: moveFind(older: false)
        case .setFindString:
            // The selection goes away with a new search, so the text is read first.
            let text = terminal.selectedText() ?? ""
            showFind()
            findBar?.field.stringValue = text
            find(text)
        default: showFind()
        }
    }

    /// Shows the bar at the top right, with the keyboard focus in its field.
    public func showFind() {
        if findBar == nil {
            let bar = TerminalFindBar()
            bar.textChanged = { [weak self] in self?.find($0) }
            bar.move = { [weak self] in self?.moveFind(older: $0) }
            bar.done = { [weak self] in self?.hideFind() }
            bar.frame.origin = NSPoint(x: bounds.maxX - bar.frame.width - 12, y: bounds.maxY - bar.frame.height - 10)
            bar.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(bar)
            findBar = bar
        }
        window?.makeFirstResponder(findBar?.field)
    }

    /// Ends Find. The selected match stays selected, so Copy takes it.
    public func hideFind() {
        guard let bar = findBar else { return }
        bar.removeFromSuperview()
        (findBar, search) = (nil, nil)
        window?.makeFirstResponder(self)
    }

    /// Looks for the text and selects its newest match.
    func find(_ text: String) {
        step { try $0.find(text) }
    }

    /// Goes to the older or the newer match. With no bar, the bar comes first.
    func moveFind(older: Bool) {
        guard findBar != nil else { return showFind() }
        step { older ? try $0.selectOlder() : try $0.selectNewer() }
    }

    private func step(_ move: (TerminalSearch) throws -> TerminalSearch.Matches) {
        do {
            let search = try search ?? TerminalSearch(terminal: terminal)
            self.search = search
            findBar?.show(try move(search))
        } catch {
            logger.error("Find failed: \(String(describing: error), privacy: .private)")
        }
        // The step can move the viewport to its match.
        scrollBar.reveal()
        requestFrame()
    }
}
