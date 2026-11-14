/// One file of the data folder.
///
/// Every file is named here, so the layout of the folder is in one place.
/// `documentation/architecture.md` describes each file.
public struct DataFile: Hashable, Sendable, CustomStringConvertible {
    /// The file name in the data folder.
    public let name: String
    /// Whether the content can sync to the other Macs of the user later.
    public let scope: DataFileScope

    init(name: String, scope: DataFileScope) {
        self.name = name
        self.scope = scope
    }

    /// The projects in the user's order, with their identifiers and names.
    public static let projects = DataFile(name: "projects.json", scope: .shared)
    /// The folder of each project on this Mac.
    public static let projectFolders = DataFile(name: "project-folders.json", scope: .thisMac)
    /// The settings that differ from their defaults.
    public static let settings = DataFile(name: "settings.json", scope: .shared)
    /// The rows of the sessions list and their splits, which the app keeps.
    public static let layout = DataFile(name: "layout.json", scope: .thisMac)

    /// The agent threads: their agents, conversations, accounts and folders.
    public static let threads = DataFile(name: "threads.json", scope: .thisMac)

    /// The terminal sessions that run, so that they come back after a
    /// restart: the folder, the name and the size of each one.
    public static let sessions = DataFile(name: "sessions.json", scope: .thisMac)

    /// The last usage reading of each account, which the app keeps.
    public static let accountUsage = DataFile(name: "account-usage.json", scope: .thisMac)

    public static let all: [DataFile] = [.projects, .projectFolders, .settings, .layout, .threads, .sessions, .accountUsage]

    public var description: String { name }
}
