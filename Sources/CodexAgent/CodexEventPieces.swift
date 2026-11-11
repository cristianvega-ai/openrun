import AgentConversation

/// The pieces of one item that Codex streams, such as the text of an
/// answer or the output of a command.
///
/// A command can print thousands of small pieces in one moment. Pieces
/// that wait for the caller join into one event, so such a burst does not
/// fill the list of the events that wait.
enum CodexEventPieces {
    /// The one event that holds `first` and then `next`, when both are
    /// pieces of the same item. It keeps the line of `first`. Any other
    /// pair gives nil.
    static func joined(_ first: ConversationEvent, _ next: ConversationEvent) -> ConversationEvent? {
        let kind: ConversationEventKind
        switch (first.kind, next.kind) {
        case (.agentTextDelta(let old), .agentTextDelta(let new)) where old.itemIdentifier == new.itemIdentifier:
            kind = .agentTextDelta(AgentTextDelta(itemIdentifier: old.itemIdentifier, text: old.text + new.text))
        case (.toolCallOutput(let old), .toolCallOutput(let new)) where old.identifier == new.identifier:
            kind = .toolCallOutput(ToolCallOutput(identifier: old.identifier, text: old.text + new.text))
        case (.toolCallInputDelta(let old), .toolCallInputDelta(let new)) where old.identifier == new.identifier:
            kind = .toolCallInputDelta(ToolCallInputDelta(identifier: old.identifier, partialInput: old.partialInput + new.partialInput))
        // The newer state of the thinking replaces the older one.
        case (.thinking(let old), .thinking(let new)) where old.itemIdentifier == new.itemIdentifier && !old.isComplete:
            kind = .thinking(new)
        default:
            return nil
        }
        return ConversationEvent(kind, sourceLine: first.sourceLine)
    }

    /// The room that an event takes while it waits: the length of the
    /// line that gave it. An event holds no more than its line did. An
    /// event that OpenRun made has no line and counts as nothing.
    static func byteCount(of event: ConversationEvent) -> Int {
        event.sourceLine?.byteCount ?? 0
    }
}
