import Foundation
import SessionConnection
import SessionProtocol
import UntrustedText

/// `openrun project list`: one line for each project, in the order of the
/// first pane, then the projects whose folder this Mac does not know. The
/// columns are the identifier, the shown name and the folder, with tabs
/// between them. The folder is empty for a project without a folder.
///
/// A client chose the name and the folder, so every field is escaped, as in
/// `openrun list`.
struct ProjectListCommand {
    var printsJSON = false

    func run(location: SocketLocation) throws -> String {
        let projects = try SessionClient(location: location).projects()
        return printsJSON ? try Self.document(of: projects) : Self.lines(of: projects)
    }

    static func lines(of projects: [ProjectSummary]) -> String {
        projects
            .map { project in
                [project.identifierText, Self.shownName(of: project), project.folder ?? ""]
                    .map(PrintableText.escaping)
                    .joined(separator: "\t") + "\n"
            }
            .joined()
    }

    /// The name, or the last name of the folder, as the first pane shows it.
    static func shownName(of project: ProjectSummary) -> String {
        if let name = project.name { return name }
        guard let folder = project.folder else { return "" }
        return folder == "/" ? "/" : (folder as NSString).lastPathComponent
    }

    /// An object with the list, as `openrun list --json` gives it. Each key
    /// is always there, with `null` for a name or a folder that is not set.
    static func document(of projects: [ProjectSummary]) throws -> String {
        let listed = projects.map { project -> [String: String?] in
            ["identifier": project.identifierText, "name": project.name, "folder": project.folder]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(["projects": listed]), as: UTF8.self) + "\n"
    }
}
