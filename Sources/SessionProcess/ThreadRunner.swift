import AgentConversation
import AgentProgram
import AgentThreads
import ClaudeCodeAgent
import Foundation

/// One agent thread in use: the process of its agent, its events, and the
/// clients that follow it (decisions of 2026-11-10).
///
/// The agent runs with JSON lines on its pipes. Each line of its output
/// becomes events. The runner keeps a transcript for the state of the
/// thread and the newest events for a client that attaches, and it gives
/// each new event to the clients that are attached. Only this actor
/// touches them, so an attach gets the kept events and then each later
/// event, with no gap and no repeat.
actor ThreadRunner {
    typealias Listener = @Sendable (ThreadDelivery) -> Void

    /// The most messages that wait behind a turn. A script could send
    /// messages without end.
    static let waitingMessageLimit = 16
    /// How long a process may take to end after a stop or a closed input,
    /// before it gets SIGTERM and then SIGKILL.
    static let endGracePeriod = Duration.seconds(5)

    struct WaitingMessage {
        let identifier: UUID
        /// The line for the standard input of the agent.
        let line: [UInt8]
    }

    var record: ThreadRecord
    var transcript = Transcript()
    var buffer: ThreadEventBuffer
    var listeners: [ObjectIdentifier: Listener] = [:]
    var program: AgentProgram?
    var decoder = ClaudeCodeOutputDecoder()
    var waitingMessages: [WaitingMessage] = []
    /// The message whose turn runs, from its send to the end of its turn
    /// or of the process.
    var activeMessage: UUID?
    /// Whether OpenRun asked the process to end: a stop, the quiet time,
    /// or the close of the thread.
    var endWasRequested = false
    var isClosed = false
    /// The time of the last message or event, for the quiet time and the
    /// limit of processes.
    var lastUse = ContinuousClock.now
    let launchSettings: @Sendable () async throws -> AgentLaunchSettings
    /// Runs after a change of the record or of a fact that a list shows.
    let changed: @Sendable (ThreadRunner) async -> Void

    init(
        record: ThreadRecord, bufferByteLimit: Int = ThreadEventBuffer.defaultByteLimit,
        launchSettings: @escaping @Sendable () async throws -> AgentLaunchSettings,
        changed: @escaping @Sendable (ThreadRunner) async -> Void = { _ in }
    ) {
        self.record = record
        buffer = ThreadEventBuffer(byteLimit: bufferByteLimit)
        (self.launchSettings, self.changed) = (launchSettings, changed)
    }

    var state: ThreadState { transcript.state }
    var isProcessRunning: Bool { program != nil }
    /// Whether a turn runs or a message waits, so the process must stay.
    var isBusy: Bool { activeMessage != nil || !waitingMessages.isEmpty }

    /// Gives an event to the transcript, the buffer and the clients.
    func emit(_ kind: ConversationEventKind, sourceLine: SourceLine? = nil) {
        let event = ConversationEvent(kind, sourceLine: sourceLine)
        _ = transcript.apply(event)
        let data = buffer.append(event)
        for listener in listeners.values { listener(.event(data)) }
        lastUse = .now
    }

    /// Attaches a client. It gets the kept events, the mark that they are
    /// complete, and then each new event, all through `listener`.
    func attach(_ key: ObjectIdentifier, listener: @escaping Listener) {
        guard !isClosed else { return listener(.closed) }
        for entry in buffer.entries { listener(.event(entry.data)) }
        listener(.replayComplete(hasEarlierEvents: buffer.hasEarlierEvents))
        listeners[key] = listener
    }

    func detach(_ key: ObjectIdentifier) {
        listeners[key] = nil
    }
}
