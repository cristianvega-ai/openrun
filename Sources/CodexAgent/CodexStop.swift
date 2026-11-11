/// What a stop of a Codex thread did.
public struct CodexStop: Sendable, Hashable {
    /// Whether Codex took the interrupt of a turn that ran.
    public var interruptedTurn: Bool
    /// The commands of the thread that OpenRun ended after the interrupt.
    public var endedCommandCount: Int
    /// Whether a command of the thread can still run, because Codex
    /// refused to list or to end them.
    public var commandsMayStillRun: Bool

    public init(interruptedTurn: Bool = false, endedCommandCount: Int = 0, commandsMayStillRun: Bool = false) {
        self.interruptedTurn = interruptedTurn
        self.endedCommandCount = endedCommandCount
        self.commandsMayStillRun = commandsMayStillRun
    }
}
