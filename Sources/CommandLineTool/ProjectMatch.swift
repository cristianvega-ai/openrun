import Projects
import SessionProtocol

/// Finds the project that the user typed: any unique start of its
/// identifier, as for a session, or else its folder.
enum ProjectMatch {
    /// A word that is the start of one identifier means that project. A
    /// word that starts no identifier, or more than one, is a folder: a
    /// relative path starts in `currentFolder`, and `~` is `homeFolder`.
    /// The folder gets the spelling that the session process gave it when
    /// it added the project, also when the folder no longer exists.
    static func find(_ typed: String, in projects: [ProjectSummary], currentFolder: String, homeFolder: String) throws -> ProjectSummary {
        let wanted = typed.lowercased()
        let byIdentifier = projects.filter { $0.identifierText.hasPrefix(wanted) }
        if let exact = byIdentifier.first(where: { $0.identifierText == wanted }) { return exact }
        if byIdentifier.count == 1 { return byIdentifier[0] }
        if let folder = folder(typed, currentFolder: currentFolder, homeFolder: homeFolder),
           let project = projects.first(where: { $0.folder == folder }) {
            return project
        }
        if byIdentifier.count > 1 {
            throw CommandLineToolError.failureWithList(
                heading: "More than one project starts with \(typed). Type more characters.",
                lines: byIdentifier.map { "  \($0.identifierText)  \($0.folder ?? "")" }
            )
        }
        throw CommandLineToolError.failure("No project has an identifier that starts with \(typed), or the folder \(typed). Run 'openrun project list' to see the projects.")
    }

    private static func folder(_ typed: String, currentFolder: String, homeFolder: String) -> String? {
        if let resolved = try? ProjectFolderPath.resolve(typed, homeFolder: homeFolder, currentFolder: currentFolder) {
            return resolved
        }
        // A folder that is gone. Its project can still be removed.
        let absolute = typed == "~" || typed.hasPrefix("~/") ? homeFolder + typed.dropFirst() : typed.hasPrefix("/") ? typed : currentFolder + "/" + typed
        return ProjectFolderPath.standardized(absolute)
    }
}
