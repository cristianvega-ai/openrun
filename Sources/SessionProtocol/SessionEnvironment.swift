import Foundation

/// The environment variables that tell a program it runs in an OpenRun session.
///
/// Every program in a session gets these. A program such as an agent hook can
/// then find the session process and its own session.
public enum SessionEnvironment {
    /// The identifier of the session.
    public static let sessionName = "OPENRUN_SESSION"
    /// The path of the socket of the session process.
    public static let socketName = "OPENRUN_SOCKET"

    /// The terminal type that the session's screen understands.
    public static let terminalType = "xterm-256color"
    /// Tells programs the screen shows 24-bit colors.
    public static let colorSupport = "truecolor"
    /// Names the terminal program, so programs can tell OpenRun from others.
    public static let terminalProgram = "OpenRun"

    /// The variables to add to the environment of a program in a session.
    public static func variables(sessionIdentifier: UUID, socketPath: String) -> [String: String] {
        [
            sessionName: SessionSummary.text(for: sessionIdentifier),
            socketName: socketPath,
            "TERM": terminalType,
            "COLORTERM": colorSupport,
            "TERM_PROGRAM": terminalProgram,
        ]
    }
}
