import Foundation

/// One row of the first pane as the table shows it.
struct ProjectsListRow: Equatable {
    var entry: ProjectsListEntry
    var name: String
    var symbol: String
    var help: String?
    var attentionCount: Int

    /// The table row of the first project, under the two fixed entries at the top.
    static let firstProjectRow = 2

    /// "All Projects" and "Needs You" first, then the projects in the user's
    /// order, then "Other Folders": the threads and the terminals in
    /// folders of no project.
    static func rows(for content: ProjectsListContent) -> [ProjectsListRow] {
        [ProjectsListRow(entry: .allSessions, name: "All Projects", symbol: "square.stack", help: "The threads and the terminals of every project", attentionCount: 0),
         ProjectsListRow(entry: .needsYou, name: "Needs You", symbol: "bell", help: nil, attentionCount: content.needsYouCount)]
            + content.projects.map {
                ProjectsListRow(entry: .project($0.identifier), name: $0.name, symbol: "folder", help: $0.folder, attentionCount: $0.attentionCount)
            }
            + [ProjectsListRow(entry: .noProject, name: "Other Folders", symbol: "tray", help: "The threads and the terminals in folders of no project", attentionCount: content.noProjectAttentionCount)]
    }

    var projectIdentifier: UUID? {
        if case .project(let identifier) = entry { identifier } else { nil }
    }

    /// The name that VoiceOver says, with the count that the row shows.
    var accessibilityLabel: String {
        guard attentionCount > 0 else { return name }
        if entry == .needsYou { return "\(name), \(attentionCount)" }
        return "\(name), \(attentionCount) need\(attentionCount == 1 ? "s" : "") you"
    }
}
