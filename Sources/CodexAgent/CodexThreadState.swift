import AgentConversation

/// What the app-server keeps for one open thread.
struct CodexThreadState {
    let channel: CodexEventChannel
    var mapper = CodexEventMapper()

    /// Sends the events of one line to the caller, in order.
    func send(_ kinds: [ConversationEventKind], line: SourceLine?) async {
        for kind in kinds { await channel.send(ConversationEvent(kind, sourceLine: line)) }
    }
}
