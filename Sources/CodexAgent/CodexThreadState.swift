import AgentConversation

/// What the app-server keeps for one open thread.
struct CodexThreadState {
    let channel: CodexEventChannel
    var mapper = CodexEventMapper()
}
