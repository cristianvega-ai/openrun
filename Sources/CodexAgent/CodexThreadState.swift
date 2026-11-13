import AgentConversation

/// What the app-server keeps for one open thread.
struct CodexThreadState {
    let channel: CodexEventChannel
    var mapper = CodexEventMapper()
    /// The `turn/start` requests of the thread that have no answer yet.
    /// Only the answer names the turn, so a stop waits for it.
    var startingTurnCount = 0
    /// A stop came before the answer to `turn/start`, so the turn that
    /// the answer names ends at once.
    var stopsTheStartingTurns = false
}
