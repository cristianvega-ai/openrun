import Foundation

/// One row of the first pane as the table shows it.
struct ProjectsListRow: Equatable {
    /// What a row is: an entry that the user selects, the heading of the
    /// projects, or the hint that shows while the user has no project.
    enum Kind: Hashable {
        case entry(ProjectsListEntry)
        case heading
        case hint
    }

    var kind: Kind
    var name: String
    var symbol: String
    var help: String?
    var attentionCount: Int

    /// The table row of the first project, under the two fixed entries at
    /// the top and the heading of the projects.
    static let firstProjectRow = 3

    /// "All Projects" and "Needs You" first, then the projects in the user's
    /// order, then "Other Folders": the threads and the terminals in
    /// folders of no project. It shows only when such work exists.
    /// The projects have the heading "Projects" over them, so a user sees
    /// that the work belongs to them.
    static func rows(for content: ProjectsListContent) -> [ProjectsListRow] {
        [ProjectsListRow(kind: .entry(.allSessions), name: "All Projects", symbol: "square.stack", help: "The threads and the terminals of every project", attentionCount: 0),
         ProjectsListRow(kind: .entry(.needsYou), name: "Needs You", symbol: "bell", help: nil, attentionCount: content.needsYouCount),
         ProjectsListRow(kind: .heading, name: "Projects", symbol: "", help: nil, attentionCount: 0)]
            + content.projects.map {
                ProjectsListRow(kind: .entry(.project($0.identifier)), name: $0.name, symbol: "folder", help: $0.folder, attentionCount: $0.attentionCount)
            }
            + (content.showsOtherFolders ? [ProjectsListRow(
                kind: .entry(.noProject), name: "Other Folders", symbol: "tray", help: "The threads and the terminals in folders of no project",
                attentionCount: content.noProjectAttentionCount)] : [])
    }

    /// The entry of a row that the user can select.
    var entry: ProjectsListEntry? {
        if case .entry(let entry) = kind { entry } else { nil }
    }

    var projectIdentifier: UUID? {
        if case .entry(.project(let identifier)) = kind { identifier } else { nil }
    }

    /// The name that VoiceOver says, with the count that the row shows.
    var accessibilityLabel: String {
        guard attentionCount > 0 else { return name }
        if entry == .needsYou { return "\(name), \(attentionCount)" }
        return "\(name), \(attentionCount) need\(attentionCount == 1 ? "s" : "") you"
    }
}
