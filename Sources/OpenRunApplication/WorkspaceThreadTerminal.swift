import AppKit
import MainWindow
import PaneAppearance
import SessionProtocol
import TerminalView

/// Open in Terminal (proposal 6): the row of a thread shows the terminal
/// session of its conversation, and Back to Chat ends that session.
extension Workspace {
    /// The terminal sessions of the threads. Each one shows in the row of
    /// its thread, so it gets no row of its own.
    var threadTerminals: [UUID: UUID] {
        Dictionary(connection.overview.threads.compactMap { thread in thread.terminalSession.map { ($0, thread.identifier) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Asks the session process for the conversation of the thread in a
    /// terminal, with the grid of the third pane.
    func openThreadInTerminal(_ thread: UUID) {
        let grid = TerminalView.estimatedGrid(for: window.contentAreaSize, scale: window.window.backingScaleFactor)
        let size = SessionSize(columns: grid.columns, rows: grid.rows)
        perform("The conversation could not open in a terminal") { _ = try $0.openThreadInTerminal(thread, size: size) }
    }

    func returnThreadFromTerminal(_ thread: UUID) {
        perform("The conversation could not go back to the chat") { try $0.returnThreadFromTerminal(thread) }
    }

    /// The button of the top row that ends the terminal session of a thread.
    func backToChatButton(for thread: UUID) -> NSButton {
        let button = BackToChatButton(title: "Back to Chat", target: self, action: #selector(backToChat(_:)))
        (button.thread, button.isBordered, button.image, button.imagePosition) = (thread, false, NSImage(systemSymbolName: "bubble.left", accessibilityDescription: nil), .imageLeading)
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    @objc func backToChat(_ sender: BackToChatButton) {
        if let thread = sender.thread { returnThreadFromTerminal(thread) }
    }
}

/// A button that knows the thread whose terminal it ends.
final class BackToChatButton: NSButton {
    var thread: UUID?
}
