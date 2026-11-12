/// A request for a thread was refused. Nothing changed.
enum ThreadRequestError: Error, Equatable, CustomStringConvertible {
    case unsupportedAgent(String)
    case folderDoesNotExist
    case onlyForClaudeCode
    case openInTerminal
    case notInTerminal
    /// The mode is no mode of the agent, or it is wider than the setting allows.
    case permissionModeNotOffered(offered: [String])

    var description: String {
        switch self {
        case .unsupportedAgent: "OpenRun runs threads with Claude Code and with Codex. Give claude-code or codex as the agent."
        case .folderDoesNotExist: "The folder of a thread must be an absolute path of a folder that exists."
        case .onlyForClaudeCode: "Only a thread with Claude Code can do that."
        case .openInTerminal: "The conversation is open in a terminal. Go back to the chat first."
        case .notInTerminal: "The conversation is not open in a terminal."
        case .permissionModeNotOffered(let offered):
            "A thread can take these permission modes: \(offered.joined(separator: ", ")). "
                + "The setting claude-code-permission-mode gives the widest one, and only the settings window of OpenRun changes it."
        }
    }
}
