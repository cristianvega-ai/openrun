import AgentConversation

/// An open Codex thread on its app-server.
///
/// Read `events` in a task of its own: while too many events wait, the
/// app-server reads no more output, for every thread of the account.
public struct CodexThread: Sendable {
    /// The identifier of the thread, which `resumeThread` takes.
    public let identifier: String
    /// The events of the thread, from its start to its close or the end of
    /// the app-server. Only one task may read them.
    public let events: AsyncStream<ConversationEvent>
    let server: CodexAppServer
}
