import Foundation

/// What a thread gives to a client that is attached to it, in order.
enum ThreadDelivery: Sendable {
    /// One event, as the JSON of a `ConversationEvent`.
    case event(Data)
    /// The events that the thread kept came before this mark, and each
    /// later event is new. `hasEarlierEvents` tells that older events went
    /// away, so the history of the agent holds more.
    case replayComplete(hasEarlierEvents: Bool)
    /// The thread closed. Nothing comes after it.
    case closed
}
