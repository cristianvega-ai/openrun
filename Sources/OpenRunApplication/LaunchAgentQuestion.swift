/// What the app tells the user about the launch agent. Each one waits for
/// the user, so the app never registers the agent again in a loop.
enum LaunchAgentQuestion: Equatable, Sendable {
    /// The user must allow the agent in System Settings, or turned it off
    /// there.
    case approvalNeeded
    /// The registration or the start failed. The detail says why.
    case failed(detail: String)

    /// The title, the text and the buttons. The first button agrees.
    var words: (title: String, message: String, buttons: [String]) {
        switch self {
        case .approvalNeeded:
            ("OpenRun needs your permission to run in the background",
             "The session process keeps your shells and agents running when the window closes. Turn on OpenRun in System Settings, General, Login Items & Extensions. Then choose File > Retry Session Process.",
             ["Open System Settings", "Not Now"])
        case .failed(let detail):
            ("OpenRun could not set up the session process", "\(detail) Choose File > Retry Session Process to try again.", ["OK"])
        }
    }
}
