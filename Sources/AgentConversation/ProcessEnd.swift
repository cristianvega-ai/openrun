/// The agent's process ended. The session process reports it.
public struct ProcessEnd: Codable, Sendable, Hashable {
    /// The exit status, when the process called exit.
    public var exitStatus: Int32?
    /// The signal that ended the process, when one did.
    public var signal: Int32?
    /// Whether OpenRun ended the process, for a stop or after a quiet time.
    public var wasRequested: Bool
    /// The end of the process's standard error, for a diagnosis.
    public var standardErrorText: String?

    public init(exitStatus: Int32?, signal: Int32? = nil, wasRequested: Bool, standardErrorText: String? = nil) {
        self.exitStatus = exitStatus
        self.signal = signal
        self.wasRequested = wasRequested
        self.standardErrorText = standardErrorText
    }

    /// Whether the end was a failure: OpenRun did not ask for it, and the
    /// process did not exit with status 0.
    public var isFailure: Bool {
        !wasRequested && (exitStatus != 0 || signal != nil)
    }
}
