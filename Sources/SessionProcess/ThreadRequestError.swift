/// A request for a thread was refused. Nothing changed.
enum ThreadRequestError: Error, Equatable, CustomStringConvertible {
    case unsupportedAgent(String)
    case folderDoesNotExist
    /// The mode is no mode of the agent, or it is wider than the setting allows.
    case permissionModeNotOffered(offered: [String])

    var description: String {
        switch self {
        case .unsupportedAgent: "OpenRun runs threads with Claude Code. Give claude-code as the agent."
        case .folderDoesNotExist: "The folder of a thread must be an absolute path of a folder that exists."
        case .permissionModeNotOffered(let offered):
            "A thread can take these permission modes: \(offered.joined(separator: ", ")). "
                + "The setting claude-code-permission-mode gives the widest one, and only the settings window of OpenRun changes it."
        }
    }
}
