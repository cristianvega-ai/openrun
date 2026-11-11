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

    /// Gives the next message that waits to the agent, when no turn runs.
    func sendNextMessage() async {
        guard activeMessage == nil, !isClosed, let message = waitingMessages.first else { return }
        waitingMessages.removeFirst()
        activeMessage = message.identifier
        do {
            var running = program
            if running == nil { running = try await startProcess() }
            try await running?.write(message.line)
        } catch {
            // The agent could not start, or it ended before it took the
            // message. The later messages would fail in the same way.
            waitingMessages = []
            if activeMessage == message.identifier {
                activeMessage = nil
                emit(.turnEnded(TurnEnd(outcome: .failed, errorText: "The agent could not take the message. \(error)")))
            }
        }
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
