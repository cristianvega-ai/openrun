/// The limits and names that an app-server uses.
public struct CodexServerOptions: Sendable, Hashable {
    /// The name and version that the handshake gives to Codex.
    public var clientName: String
    public var clientVersion: String
    /// How long a request waits for its answer.
    public var answerTimeLimit: Duration
    /// How long an approval waits for the user. After it, OpenRun declines.
    public var approvalTimeLimit: Duration
    /// How long a stop waits for the end of the turn before it ends the
    /// commands of the thread.
    public var stopTimeLimit: Duration
    /// The most events of a thread that wait for the caller. A thread with
    /// more ends with an error.
    public var eventLimit: Int
    /// The longest line of the app-server that OpenRun reads.
    public var lineByteLimit: Int

    public init(
        clientName: String = "openrun", clientVersion: String = "0.1.0", answerTimeLimit: Duration = .seconds(60),
        approvalTimeLimit: Duration = .seconds(600), stopTimeLimit: Duration = .seconds(5), eventLimit: Int = 1_024,
        lineByteLimit: Int = 16 * 1024 * 1024
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.answerTimeLimit = answerTimeLimit
        self.approvalTimeLimit = approvalTimeLimit
        self.stopTimeLimit = stopTimeLimit
        self.eventLimit = eventLimit
        self.lineByteLimit = lineByteLimit
    }
}
