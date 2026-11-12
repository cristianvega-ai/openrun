import AgentConversation
import AgentProgram
import AgentThreads
import ClaudeCodeAgent
import Foundation

/// The messages of the user, the stop and the close of a thread.
extension ThreadRunner {
    /// Takes a message of the user. It goes to the agent at once when no
    /// turn runs. Else it waits behind the turn, because a stop ends the
    /// process of the agent, and a message in the agent would go with it.
    ///
    /// - Returns: The identifier of the message, which its events carry.
    @discardableResult
    func send(text: String, images: [MessageImage] = []) async throws -> UUID {
        guard !isClosed else { throw ThreadRunnerError.threadIsClosed }
        guard !isInTerminal else { throw ThreadRequestError.openInTerminal }
        guard waitingMessages.count < Self.waitingMessageLimit else {
            throw ThreadRunnerError.tooManyWaitingMessages(limit: Self.waitingMessageLimit)
        }
        let identifier = UUID()
        let line = try ClaudeCodeUserMessage.line(identifier: identifier, text: text, images: images)
        waitingMessages.append(WaitingMessage(identifier: identifier, line: line))
        // The chat shows the message at once. The agent echoes it with the
        // same identifier when it takes it.
        emit(.userMessage(UserMessage(identifier: identifier.uuidString.lowercased(), text: text, imageCount: images.count, isAccepted: false)))
        if record.title == nil { record.title = ThreadList.title(from: text) }
        await changed(self)
        await sendNextMessage()
        return identifier
    }

    /// The user gave the thread a new name, which the registry saved.
    func setName(_ name: String?) {
        record.name = name
    }

    func setInTerminal() {
        isInTerminal = true
    }

    /// The terminal session of the thread ended. The turns that the user
    /// made there come into the events, and the thread takes messages again.
    func returnedFromTerminal(events: [ConversationEvent]) async {
        // The conversation has turns now, also when the terminal started it.
        (isInTerminal, record.hasConversation) = (false, true)
        for event in events { emit(event.kind, sourceLine: event.sourceLine) }
        await changed(self)
    }

    /// The user chose another model or permission mode, which the
    /// registry saved. Claude Code takes both only at its start. So a
    /// process with no work ends now, and a process in a turn ends after
    /// the turn. The next message starts a process with the new values.
    func setLaunchFacts(model: String, permissionMode: String) async {
        guard (record.model, record.permissionMode) != (model, permissionMode) else { return }
        (record.model, record.permissionMode) = (model, permissionMode)
        guard program != nil else { return }
        if activeMessage == nil { await endProcess() } else { endsAfterTurn = true }
    }

    /// Gives the next message that waits to the agent, when no turn runs.
    /// A process that OpenRun asked to end takes no message: its end
    /// brings the next call, which starts a new process.
    func sendNextMessage() async {
        let isEnding = program != nil && endWasRequested
        guard activeMessage == nil, !isClosed, !isStartingProcess, !isEnding, let message = waitingMessages.first else { return }
        var isActive = false
        do {
            var running = program
            if running == nil {
                isStartingProcess = true
                defer { isStartingProcess = false }
                guard await hasProcessSlot() else { return await changed(self) }
                running = try await startProcess()
            }
            // The thread closed during the start, so its new process must end too.
            guard !isClosed else { return await running?.terminate(gracePeriod: .seconds(1)) ?? () }
            // A stop during the start removed the message.
            guard waitingMessages.first?.identifier == message.identifier else { return await processHasNoWork() }
            waitingMessages.removeFirst()
            (activeMessage, isActive) = (message.identifier, true)
            try await running?.write(message.line)
        } catch {
            // The agent could not start, or it ended before it took the
            // message. The later messages would fail in the same way. An
            // agent that ended during the write gave its own end.
            waitingMessages = []
            if !isActive || activeMessage == message.identifier {
                activeMessage = nil
                emit(.turnEnded(TurnEnd(outcome: .failed, errorText: "The agent could not take the message. \(error)")))
            }
        }
        await changed(self)
    }

    /// Asks for a slot for the process. While every slot is taken, the
    /// messages wait, and the chat says why one time.
    private func hasProcessSlot() async -> Bool {
        let answer = await takeProcessSlot(record.identifier)
        if case .waits(let limit) = answer, !waitsForProcessSlot {
            let agents = limit == 1 ? "1 agent" : "\(limit) agents"
            emit(.notice(Notice(level: .information, text: "The message waits, because OpenRun runs at most \(agents) at one time. It goes out when another agent ends its work.")))
        }
        waitsForProcessSlot = answer != .granted
        return answer == .granted
    }

    /// The process runs with no turn and no message: the quiet time starts.
    func processHasNoWork() async {
        watchForQuietTime()
        await changed(self)
    }

    /// Stops the turn. Claude Code ends its turn and its process at
    /// SIGINT, and the next message resumes the conversation. The messages
    /// that waited behind the turn do not go out. A stop when nothing
    /// runs changes nothing.
    func stop() async {
        if !waitingMessages.isEmpty {
            emit(.notice(Notice(level: .information, text: "The stop removed \(waitingMessages.count) messages that waited for the agent.")))
            waitingMessages = []
        }
        endPermissions()
        guard let program, activeMessage != nil else { return await changed(self) }
        endWasRequested = true
        program.send(signal: SIGINT)
        await endAfterGrace(program)
    }

    /// Closes the thread: its process ends, and its clients hear of it.
    func close() async {
        guard !isClosed else { return }
        (isClosed, waitingMessages, endWasRequested) = (true, [], true)
        endPermissions()
        for listener in listeners.values { listener(.closed) }
        listeners = [:]
        if let program { await program.terminate(gracePeriod: .seconds(1)) }
    }
}
