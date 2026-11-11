import Foundation
import SessionProtocol
import SessionsList
import WindowLayout

/// Makes the row of the second pane from the facts of its sessions
/// (decisions of 2026-11-10). A program chose some of the texts. The
/// session process bounded and cleaned them, and a row shows them as
/// plain text.
public enum SessionRowFacts {
    /// What a row with no text in its alert says, such as after the bell.
    public static let alertWithoutText = "Needs your attention"

    /// The row, or nil when none of its sessions runs.
    ///
    /// - Parameters:
    ///   - sessions: Gives the facts of a session that runs.
    ///   - inView: The session that the user looks at and types into. Its
    ///     alert shows no mark, because the app clears it at once.
    ///   - home: The home folder, which a row shows as `~`.
    public static func display(of row: LayoutRow, sessions: (UUID) -> SessionSummary?, inView: UUID?, home: String) -> SessionRowDisplay? {
        let facts = row.pane.sessions.compactMap(sessions)
        guard let first = facts.first else { return nil }
        let alert = facts.first { $0.alert != nil && $0.identifier != inView }?.alert
        let times = facts.flatMap { [$0.createdAt, $0.lastOutputAt, $0.lastInputAt].compactMap(\.self) }
        return SessionRowDisplay(
            identifier: row.identifier, title: title(of: first, home: home),
            folder: FolderText.shown(first.currentFolder ?? first.folder, home: home), branch: first.branch, kind: .terminal,
            isInProgress: facts.contains { $0.isInProgress == true },
            alert: alert.map { $0.text.isEmpty ? alertWithoutText : $0.text },
            lastActivity: times.max() ?? first.createdAt, startTime: first.createdAt)
    }

    /// The name that the user gave, or the title that the program set, or
    /// the program with the last name of its folder, such as `zsh — openrun`.
    public static func title(of session: SessionSummary, home: String) -> String {
        if let name = session.name, !name.isEmpty { return name }
        if let title = session.title, !title.isEmpty { return title }
        let program = session.foregroundProgram ?? session.command.first.map { ($0 as NSString).lastPathComponent } ?? ""
        let folder = FolderText.lastName(of: session.currentFolder ?? session.folder, home: home)
        return [program, folder].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}
