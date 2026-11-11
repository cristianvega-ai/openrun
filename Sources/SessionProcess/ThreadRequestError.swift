/// A request for a thread was refused. Nothing changed.
enum ThreadRequestError: Error, Equatable, CustomStringConvertible {
    case unsupportedAgent(String)
    case folderDoesNotExist

    var description: String {
        switch self {
        case .unsupportedAgent: "OpenRun runs threads with Claude Code. Give claude-code as the agent."
        case .folderDoesNotExist: "The folder of a thread must be an absolute path of a folder that exists."
        }
    }
}
