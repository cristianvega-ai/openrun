import AgentConversation
import AgentThreads
import CodexAgent
import Foundation

/// One Codex thread in use (decisions of 2026-11-10). Codex has one
/// app-server for each account, for all threads of that account, so this
/// runner holds no process: it opens its thread on that app-server with
/// its first message, and it resumes the thread after a restart.
actor CodexThreadRunner {
    /// The model word of a thread that takes the model of the user's
    /// configuration of Codex.
    static let configuredModel = "default"

    var record: ThreadRecord
    var transcript = Transcript()
    var buffer = ThreadEventBuffer()
    var listeners: [ObjectIdentifier: ThreadRunner.Listener] = [:]
    var thread: CodexThread?
    var waitingMessages: [CodexTurn] = []
    /// Whether a turn runs, from its start to its end.
    var isTurnRunning = false
    var isClosed = false
    var usageReadAt: Date?
    let hadConversationAtStart: Bool
    /// Opens the app-servers of the accounts, at the first need.
    let servers: @Sendable () async throws -> CodexAccountServers
    let changed: @Sendable (CodexThreadRunner) async -> Void

    init(record: ThreadRecord, servers: @escaping @Sendable () async throws -> CodexAccountServers, changed: @escaping @Sendable (CodexThreadRunner) async -> Void = { _ in }) {
        (self.record, hadConversationAtStart, self.servers, self.changed) = (record, record.hasConversation, servers, changed)
    }

    /// What the registry reads of the runner, in one step.
    var facts: (record: ThreadRecord, state: ThreadState, isOpen: Bool, waitingMessageCount: Int, usage: UsageReading?, usageReadAt: Date?) {
        (record, transcript.state, isTurnRunning, waitingMessages.count, transcript.usage, usageReadAt)
    }

    func emit(_ event: ConversationEvent) {
        _ = transcript.apply(event)
        if case .usage = event.kind { usageReadAt = Date() }
        let data = buffer.append(event)
        for listener in listeners.values { listener(.event(data)) }
    }

    func attach(_ key: ObjectIdentifier, listener: @escaping ThreadRunner.Listener) {
        guard !isClosed else { return listener(.closed) }
        for entry in buffer.entries { listener(.event(entry.data)) }
        listener(.replayComplete(hasEarlierEvents: buffer.hasEarlierEvents || hadConversationAtStart))
        listeners[key] = listener
    }

    func detach(_ key: ObjectIdentifier) {
        listeners[key] = nil
    }

    func setName(_ name: String?) {
        record.name = name
    }

    /// The user chose another model or sandbox. Codex takes both with the next turn.
    func setTurnFacts(model: String, permissionMode: String) {
        (record.model, record.permissionMode) = (model, permissionMode)
    }
}
