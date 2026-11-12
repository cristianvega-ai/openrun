import Foundation

/// A condition of a thread that the chat shows apart from its transcript.
///
/// An agent whose process does not run is no condition: the next message
/// starts it.
public enum ChatThreadCondition: Equatable, Hashable, Sendable {
    /// The thread takes messages.
    case ready
    /// The agent's process could not start.
    /// - Parameters:
    ///   - reason: What went wrong, such as "claude was not found".
    ///   - advice: What the user can do, such as installing the agent.
    case startFailed(reason: String, advice: String)
    /// The account reached its usage limit (proposal 8 of 2026-11-10). The
    /// thread waits for the reset, and the chat offers a new thread on one
    /// of the other accounts.
    case atLimit(resetTime: Date?, otherAccounts: [ChatAccount])
    /// The agent has no valid login under the account of the thread. The
    /// user signs in with the agent in a terminal, or goes on in a new
    /// thread under one of the other accounts.
    case notSignedIn(otherAccounts: [ChatAccount])
    /// The conversation is open in a terminal session (proposal 6), so the
    /// chat only shows it until the user comes back.
    case openInTerminal
}
