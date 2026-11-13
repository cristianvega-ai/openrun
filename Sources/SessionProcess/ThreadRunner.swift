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
    /// The longest wait for the answer of the user to a permission
    /// request: 24 hours, as long as the hook of the agent may wait.
    static let permissionTimeLimit = Duration.seconds(ClaudeCodeLaunch.hookTimeoutSeconds)
    /// How long a process with no work stays: five minutes (decision of
    /// 2026-11-10). A resume takes less than a second.
    static let defaultQuietTime = Duration.seconds(300)

    struct WaitingMessage {
        let identifier: UUID
        /// The line for the standard input of the agent.
        let line: [UInt8]
    }

    var record: ThreadRecord
    /// Whether the conversation had turns before this runner came into
    /// use, such as before a restart of the session process. The history
    /// of the agent holds them, and the events of this runner do not.
    let hadConversationAtStart: Bool
    var transcript = Transcript()
    var buffer: ThreadEventBuffer
    var listeners: [ObjectIdentifier: Listener] = [:]
    var program: AgentProgram?
    var decoder = ClaudeCodeOutputDecoder()
    var waitingMessages: [WaitingMessage] = []
    /// The permission requests that wait for the user, by identifier.
    var waitingPermissions: [String: WaitingPermission] = [:]
    /// Finds the tool call that a permission request is for.
    var toolCalls = ClaudeCodeToolCallMatcher()
    /// The message whose turn runs, from its send to the end of its turn
    /// or of the process.
    var activeMessage: UUID?
    /// Whether OpenRun asked the process to end: a stop, the quiet time,
    /// or the close of the thread.
    var endWasRequested = false
    var isClosed = false
    /// Whether the runner asks for a slot or starts its process now. The
    /// messages wait until that has finished.
    var isStartingProcess = false
    /// Whether a call to send the next message came while a start ran.
    var startRequestedWhileStarting = false
    /// Whether a message waits because every slot for a process is taken.
    var waitsForProcessSlot = false
    /// Whether the process must end after the turn that runs, because
    /// the user chose another model or permission mode.
    var endsAfterTurn = false
    /// Whether the conversation is open in a terminal session (proposal
    /// 6). A second process on it would split the conversation in two,
    /// so the thread takes no message until the session ends.
    var isInTerminal = false
    /// The time of the newest usage reading of the agent.
    var usageReadAt: Date?
    /// The wait for the quiet time of the process.
    var quietTask: Task<Void, Never>?
    /// The gate of the registry, so a runner that a caller already holds starts no work after the shutdown.
    let admission: ThreadAdmission
    let quietTime: Duration
    /// The time of the last message or event, for the quiet time and the
    /// limit of processes.
    var lastUse = ContinuousClock.now
    let launchSettings: @Sendable () async throws -> AgentLaunchSettings
    /// Asks the registry whether this thread may run a process now.
    let takeProcessSlot: @Sendable (UUID) async -> ProcessSlotAnswer
    /// Runs after a change of the record or of a fact that a list shows.
    let changed: @Sendable (ThreadRunner) async -> Void

    init(
        record: ThreadRecord, bufferByteLimit: Int = ThreadEventBuffer.defaultByteLimit, quietTime: Duration = ThreadRunner.defaultQuietTime,
        launchSettings: @escaping @Sendable () async throws -> AgentLaunchSettings,
        admission: ThreadAdmission = ThreadAdmission(),
        takeProcessSlot: @escaping @Sendable (UUID) async -> ProcessSlotAnswer = { _ in .granted },
        changed: @escaping @Sendable (ThreadRunner) async -> Void = { _ in }
    ) {
        self.admission = admission
        (self.record, hadConversationAtStart) = (record, record.hasConversation)
        buffer = ThreadEventBuffer(byteLimit: bufferByteLimit)
        (self.quietTime, self.launchSettings, self.takeProcessSlot, self.changed) = (quietTime, launchSettings, takeProcessSlot, changed)
    }

    var state: ThreadState { transcript.state }
    var isProcessRunning: Bool { program != nil }
    /// Whether a turn runs or a message waits, so the process must stay.
    var isBusy: Bool { activeMessage != nil || !waitingMessages.isEmpty }
    /// Since when the process has had no work. Nil when it has work, when
    /// OpenRun asked it to end, or when no process runs.
    var idleSince: ContinuousClock.Instant? {
        program != nil && !endWasRequested && !isBusy && !isStartingProcess ? lastUse : nil
    }

    /// What the registry reads of the runner, in one step.
    var facts: (record: ThreadRecord, state: ThreadState, process: pid_t?, waitingMessageCount: Int, holdsProcessSlot: Bool) {
        (record, transcript.state, program?.processIdentifier, waitingMessages.count, program != nil || isStartingProcess)
    }

    /// The newest usage reading of the account and the time when it came.
    var usage: (reading: UsageReading, readAt: Date)? {
        guard let reading = transcript.usage, let usageReadAt else { return nil }
        return (reading, usageReadAt)
    }

    /// Gives an event to the transcript, the buffer and the clients.
    func emit(_ kind: ConversationEventKind, sourceLine: SourceLine? = nil) {
        let event = ConversationEvent(kind, sourceLine: sourceLine)
        _ = transcript.apply(event)
        toolCalls.observe(event)
        if case .usage = kind { usageReadAt = Date() }
        let data = buffer.append(event)
        for listener in listeners.values { listener(.event(data)) }
        lastUse = .now
    }

    /// Attaches a client. It gets the kept events, the mark that they are
    /// complete, and then each new event, all through `listener`.
    func attach(_ key: ObjectIdentifier, listener: @escaping Listener) {
        guard !isClosed else { return listener(.closed) }
        for entry in buffer.entries { listener(.event(entry.data)) }
        listener(.replayComplete(hasEarlierEvents: buffer.hasEarlierEvents || hadConversationAtStart))
        listeners[key] = listener
    }

    func detach(_ key: ObjectIdentifier) {
        listeners[key] = nil
    }
}
