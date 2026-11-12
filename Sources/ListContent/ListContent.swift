import Foundation
import ProjectsList
import SessionOverview
import SessionProtocol
import SessionsList
import WindowLayout

/// What the two lists of the main window show: the rows of each entry of
/// the first pane, and the counts of the rows that need the user. It is
/// made again after each batch of changes, which costs little for one
/// hundred sessions.
public struct ListContent {
    /// What the first pane shows as the folder of a project that has no
    /// folder on this Mac. Such a project holds no session, and the user
    /// can remove it.
    static let missingFolder = "No folder on this Mac"

    /// The rows in the user's order, each with the project of its first
    /// split and the folder of its work.
    private let rows: [(display: SessionRowDisplay, project: UUID?, folder: String)]
    private let projectSummaries: [ProjectSummary]
    private let accounts: [AccountUsageDisplay]
    private let home: String

    /// - Parameter inView: The session that the user looks at and types
    ///   into. It shows no alert.
    public init(overview: SessionOverview, layout: WindowLayout, inView: UUID?, home: String = NSHomeDirectory()) {
        let sessions = Dictionary(overview.sessions.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        // A session can name a project that a newer list no longer holds.
        let known = Set(overview.projects.filter { $0.folder != nil }.map(\.identifier))
        let threads = Dictionary(overview.threads.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        rows = layout.rows.compactMap { row in
            if let identifier = row.pane.leadingThread {
                guard let thread = threads[identifier] else { return nil }
                let display = ThreadRowFacts.display(of: row, thread: thread, inView: identifier == inView, home: home)
                return (display, thread.projectIdentifier.flatMap { known.contains($0) ? $0 : nil }, thread.folder)
            }
            guard let display = SessionRowFacts.display(of: row, sessions: { sessions[$0] }, inView: inView, home: home) else { return nil }
            let first = row.pane.sessions.lazy.compactMap { sessions[$0] }.first
            return (display, first?.projectIdentifier.flatMap { known.contains($0) ? $0 : nil }, first?.currentFolder ?? first?.folder ?? "")
        }
        (projectSummaries, accounts, self.home) = (overview.projects, AccountUsageFacts.displays(of: overview.threads), home)
    }

    /// The content of the first pane.
    public var projects: ProjectsListContent {
        let attention = rows.filter { $0.display.alert != nil }
        let displays = projectSummaries.map { project in
            ProjectDisplay(identifier: project.identifier, name: Self.name(of: project),
                           folder: project.folder.map { FolderText.shown($0, home: home) } ?? Self.missingFolder,
                           attentionCount: attention.count { $0.project == project.identifier })
        }
        return ProjectsListContent(projects: displays, needsYouCount: attention.count, accounts: accounts)
    }

    /// The rows of one entry of the first pane, in the user's order.
    public func rows(of entry: ProjectsListEntry) -> [SessionRowDisplay] {
        switch entry {
        case .allSessions: rows.map { placed($0, inListOfItsProject: false) }
        case .needsYou: rows.filter { $0.display.alert != nil }.map { placed($0, inListOfItsProject: false) }
        case .project(let identifier): rows.filter { $0.project == identifier }.map { placed($0, inListOfItsProject: true) }
        }
    }

    /// The row with its place told by its project, so a user sees that
    /// the work belongs to the project: the name of the project and the
    /// folder under it in a list of many projects, and only the folder
    /// under it in the list of the project itself.
    private func placed(_ row: (display: SessionRowDisplay, project: UUID?, folder: String), inListOfItsProject: Bool) -> SessionRowDisplay {
        guard let project = projectSummaries.first(where: { $0.identifier == row.project }), let root = project.folder,
              row.folder == root || row.folder.hasPrefix(root + "/") else { return row.display }
        let under = String(row.folder.dropFirst(root.count + 1))
        var display = row.display
        if !inListOfItsProject {
            display.folder = under.isEmpty ? Self.name(of: project) : Self.name(of: project) + "/" + under
        } else if !under.isEmpty || display.branch != nil || display.kind != .terminal {
            // A terminal with no other fact keeps its folder, so its second line is not empty.
            display.folder = under
        }
        return display
    }

    /// The name of an entry, which the second pane shows as its title.
    public func title(of entry: ProjectsListEntry) -> String {
        switch entry {
        case .allSessions: "All Projects"
        case .needsYou: "Needs You"
        case .project(let identifier): projectSummaries.first { $0.identifier == identifier }.map(Self.name(of:)) ?? ""
        }
    }

    /// Where the new work of an entry starts, for the menu of the
    /// new-session button: in the selected project, or else in the home
    /// folder.
    public func place(of entry: ProjectsListEntry) -> String {
        if case .project = entry { "In " + title(of: entry) } else { "In Your Home Folder" }
    }

    /// What the second pane says while an entry has no row.
    public func emptyMessage(of entry: ProjectsListEntry) -> String? {
        switch entry {
        case .project: "Nothing in \(title(of: entry)) Yet"
        case .needsYou: "Nothing Needs You"
        case .allSessions: nil
        }
    }

    /// The name that the user gave, or the last name of the folder.
    static func name(of project: ProjectSummary) -> String {
        if let name = project.name, !name.isEmpty { return name }
        return project.folder.map { ($0 as NSString).lastPathComponent } ?? "Project"
    }
}
