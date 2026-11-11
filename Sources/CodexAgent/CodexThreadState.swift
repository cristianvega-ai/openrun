import AgentConversation

/// What the app-server keeps for one open thread.
struct CodexThreadState {
    let channel: CodexEventChannel
    var mapper = CodexEventMapper()

    /// Sends the events of one line to the caller, in order, without a
    /// wait. Events above the limit of the channel go nowhere.
    func send(_ kinds: [ConversationEventKind], line: SourceLine?) async {
        for kind in kinds { channel.add(ConversationEvent(kind, sourceLine: line)) }
    }
}
