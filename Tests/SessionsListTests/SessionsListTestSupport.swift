import AppKit
@testable import SessionsList

/// Keeps what the second pane reports.
@MainActor
final class RecordingSessionsHost: SessionsListDelegate {
    var selections: [UUID?] = []
    var opens: [UUID] = []
    var requests: [NewSessionRequest] = []
    var renames: [(UUID, String)] = []
    var closes: [UUID] = []
    var arrangements: [(SessionsFilter, SessionsOrder)] = []

    func sessionsList(_ list: SessionsListController, didSelect identifier: UUID?) { selections.append(identifier) }
    func sessionsList(_ list: SessionsListController, didOpen identifier: UUID) { opens.append(identifier) }
    func sessionsList(_ list: SessionsListController, didRequest request: NewSessionRequest) { requests.append(request) }
    func sessionsList(_ list: SessionsListController, didRename identifier: UUID, to name: String) { renames.append((identifier, name)) }
    func sessionsList(_ list: SessionsListController, didClose identifier: UUID) { closes.append(identifier) }
    func sessionsList(_ list: SessionsListController, didChange filter: SessionsFilter, order: SessionsOrder) { arrangements.append((filter, order)) }
}

/// A second pane in a window, with four rows: a thread in progress, a
/// terminal that needs the user, a finished thread, and a finished terminal.
@MainActor
func makeSessionsList() -> (SessionsListController, RecordingSessionsHost, NSWindow, [UUID]) {
    _ = NSApplication.shared
    let list = SessionsListController(), host = RecordingSessionsHost()
    list.delegate = host
    list.now = { Date(timeIntervalSince1970: 10_000) }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = list.view
    let identifiers = (0..<4).map { _ in UUID() }
    let rows = [("Repair the resize", true, nil, 9_000.0), ("zsh", false, "Build failed", 8_000), ("Write the tests", false, nil, 9_500), ("logs", false, nil, 100)]
    list.show(SessionsListContent(title: "openrun", rows: zip(identifiers, rows).map { identifier, row in
        SessionRowDisplay(identifier: identifier, title: row.0, detail: "~/Projects/openrun · main", kind: row.0 == "zsh" || row.0 == "logs" ? .terminal : .agentThread(agent: "Claude Code", model: nil, account: nil),
                          isInProgress: row.1, alert: row.2, lastActivity: Date(timeIntervalSince1970: row.3), startTime: Date(timeIntervalSince1970: row.3))
    }, agents: ["Claude Code", "Codex"]))
    window.layoutIfNeeded()
    return (list, host, window, identifiers)
}

extension SessionsListController {
    func cell(at row: Int) -> SessionCellView? {
        table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SessionCellView
    }

    var shownTitles: [String] { rows.map(\.title) }
}
