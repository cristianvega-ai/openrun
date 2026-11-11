import Foundation
import ProjectsList
import SessionsList

/// The projects and sessions of the pictures: three projects and eight rows
/// in mixed states, as a day of work looks.
struct PictureSample {
    let now = Date()
    let projectIdentifiers = [UUID(), UUID(), UUID()]

    var projects: ProjectsListContent {
        let names = ["openrun", "website", "infrastructure-terraform-modules"]
        let counts = [2, 0, 1]
        return ProjectsListContent(projects: (0..<3).map {
            ProjectDisplay(identifier: projectIdentifiers[$0], name: names[$0], folder: "~/Projects/\(names[$0])", attentionCount: counts[$0])
        }, needsYouCount: 3, noProjectAttentionCount: 0)
    }

    /// Made once, so the identifiers of the rows stay the same.
    private(set) lazy var sessions = makeSessions()

    private func makeSessions() -> SessionsListContent {
        let claude = SessionKind.agentThread(agent: "Claude Code", model: "Opus", account: "Work")
        let codex = SessionKind.agentThread(agent: "Codex", model: "GPT-5", account: nil)
        let rows: [(String, String?, SessionKind, Bool, String?, Double)] = [
            ("Add the three-pane window", "window", claude, true, nil, 0.2),
            ("Repair the resize", "main", .terminal, false, nil, 3),
            ("Review the socket protocol", "review", codex, false, "Approve the edit of SessionProtocol.swift?", 6),
            ("swift test", "main", .terminal, true, nil, 0.1),
            ("Write the release notes for version 1 of OpenRun and the website", "notes", claude, false, nil, 48),
            ("zsh", nil, .terminal, false, "Build failed", 12),
            ("Profile the renderer", "renderer-and-the-glyph-atlas", codex, false, nil, 130),
            ("server", "main", .terminal, false, nil, 3 * 24 * 60),
        ]
        return SessionsListContent(title: "openrun", rows: rows.map { row in
            SessionRowDisplay(identifier: UUID(), title: row.0, folder: "~/Projects/openrun/Sources/TerminalRendering", branch: row.1, kind: row.2, isInProgress: row.3, alert: row.4,
                              lastActivity: now.addingTimeInterval(-60 * row.5), startTime: now.addingTimeInterval(-3_600))
        }, agents: ["Claude Code", "Codex"])
    }
}
