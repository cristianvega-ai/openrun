import UntrustedText

/// One more account of an agent: a name to show, and the folder of the
/// agent's settings, which selects the login (decision of 2026-11-10).
/// The account that the login shell of the user gives needs no entry.
public struct AgentAccount: Hashable, Sendable {
    public let name: String
    /// `CLAUDE_CONFIG_DIR` for Claude Code, `CODEX_HOME` for Codex.
    public let settingsFolder: String

    public static let nameLengthLimit = 50
    public static let folderLengthLimit = 1000
    /// More accounts than this do not fit in the menu of the button.
    public static let countLimit = 10

    public init(name: String, settingsFolder: String) {
        (self.name, self.settingsFolder) = (name, settingsFolder)
    }

    /// Whether the settings can hold this entry: a plain name and a plain
    /// full path. The folder can be away for a time, as on a disk that
    /// is not connected, so nothing checks that it exists.
    var isValid: Bool {
        PlainName.isValid(name, lengthLimit: Self.nameLengthLimit)
            && settingsFolder.hasPrefix("/") && PlainName.isValid(settingsFolder, lengthLimit: Self.folderLengthLimit)
    }
}
