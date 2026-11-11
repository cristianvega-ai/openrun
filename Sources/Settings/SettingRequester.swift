/// Who asks for a change of a setting. The session process tells which one
/// from the program at the other end of the connection.
public enum SettingRequester: Hashable, Sendable {
    /// OpenRun.app, the only program that can change a protected setting.
    case application
    /// The command-line tool, an agent, a script or any other client.
    case otherClient
}
