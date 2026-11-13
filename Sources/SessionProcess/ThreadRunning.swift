import AgentConversation
import Foundation

/// What each thread in use does for its clients, whatever its agent: the
/// runner of a Claude Code thread, and the runner of a Codex thread.
protocol ThreadRunning: Actor {
    /// Attaches a client. It gets the kept events, the mark that they are
    /// complete, and then each new event.
    func attach(_ key: ObjectIdentifier, listener: @escaping ThreadRunner.Listener)
    func detach(_ key: ObjectIdentifier)
    /// Takes a message of the user, and returns its identifier.
    @discardableResult
    func send(text: String, images: [MessageImage]) async throws -> UUID
    func stop() async
    func close() async
    /// Takes the thread for Open in Terminal before the first wait, so a
    /// second handoff or a message cannot start in between (proposal 6).
    func reserveForTerminal() throws -> UUID
    func cancelTerminalHandoff(_ reservation: UUID)
    func setName(_ name: String?)
    /// The answer of the user to a permission request. False when the
    /// request does not wait any more.
    func answerPermission(_ request: String, allows: Bool, message: String?) async -> Bool
}

extension ThreadRunner: ThreadRunning {}
extension CodexThreadRunner: ThreadRunning {}
