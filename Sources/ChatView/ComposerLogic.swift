/// What the keys and the send control of the composer do, apart from the
/// view.
///
/// While the agent works, a message waits and goes when the turn ends, so
/// the user can write the next step at once. Escape stops a turn only on a
/// second press, because a first press often only closes a menu or clears
/// a thought.
struct ComposerLogic: Equatable {
    enum Effect: Equatable {
        case none
        case send(ChatOutgoingMessage)
        case stop
    }

    /// Whether the agent works on a turn now.
    private(set) var isBusy = false
    /// The message that goes when the turn ends.
    private(set) var heldMessage: ChatOutgoingMessage?
    /// Whether one press of Escape on an empty field came already.
    private(set) var isEscapeArmed = false

    /// The user sends a message with Return or the send control.
    mutating func submit(_ message: ChatOutgoingMessage) -> Effect {
        isEscapeArmed = false
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !message.images.isEmpty else { return .none }
        let trimmed = ChatOutgoingMessage(text: text, images: message.images)
        guard isBusy else { return .send(trimmed) }
        if let held = heldMessage {
            heldMessage = ChatOutgoingMessage(text: held.text + "\n\n" + text, images: held.images + message.images)
        } else {
            heldMessage = trimmed
        }
        return .none
    }

    /// The transcript tells whether the agent works. When a turn ends, the
    /// held message goes.
    mutating func setBusy(_ busy: Bool) -> Effect {
        defer { isBusy = busy }
        guard isBusy, !busy, let held = heldMessage else { return .none }
        heldMessage = nil
        isEscapeArmed = false
        return .send(held)
    }

    /// Escape on the field. Only a second press on an empty field stops.
    mutating func escape(isFieldEmpty: Bool) -> Effect {
        guard isBusy, isFieldEmpty else {
            isEscapeArmed = false
            return .none
        }
        if isEscapeArmed {
            isEscapeArmed = false
            return .stop
        }
        isEscapeArmed = true
        return .none
    }

    /// The user takes the held message back to change it.
    mutating func takeHeldMessage() -> ChatOutgoingMessage? {
        defer { heldMessage = nil }
        return heldMessage
    }
}
