import AgentConversation
import AgentThreads
import CodexAgent
import Foundation

/// The messages, the turns, the stop and the close of a Codex thread.
extension CodexThreadRunner {
    @discardableResult
    func send(text: String, images: [MessageImage] = []) async throws -> UUID {
        guard !isClosed else { throw ThreadRunnerError.threadIsClosed }
        guard !isInTerminal else { throw ThreadRequestError.openInTerminal }
        guard waitingMessages.count < ThreadRunner.waitingMessageLimit else {
            throw ThreadRunnerError.tooManyWaitingMessages(limit: ThreadRunner.waitingMessageLimit)
        }
        let identifier = UUID()
        let model = record.model == Self.configuredModel ? nil : record.model
        waitingMessages.append(CodexTurn(
            messageIdentifier: identifier.uuidString.lowercased(), text: text, images: images, model: model, sandbox: CodexSandbox(rawValue: record.permissionMode)))
        if record.title == nil { record.title = ThreadList.title(from: text) }
        await sendNextMessage()
        return identifier
    }

    /// Starts the turn of the next message that waits, when no turn runs.
    func sendNextMessage() async {
        guard !isTurnRunning, !isClosed, let turn = waitingMessages.first else { return await changed(self) }
        waitingMessages.removeFirst()
        isTurnRunning = true
        do {
            try await openThread().startTurn(turn)
        } catch {
            // The app-server could not start, or it refused the turn. The later messages would fail in the same way.
            (isTurnRunning, waitingMessages) = (false, [])
            emit(ConversationEvent(.userMessage(UserMessage(identifier: turn.messageIdentifier, text: turn.text, imageCount: turn.images.count, isAccepted: false))))
            emit(ConversationEvent(.turnEnded(TurnEnd(outcome: .failed, errorText: "Codex could not take the message. \(error)"))))
        }
        await changed(self)
    }

    /// The thread on the app-server of its account. The first open starts
    /// a thread of Codex, and each later one resumes it by its identifier.
    func openThread() async throws -> CodexThread {
        if let thread { return thread }
        // A caller that comes while the open runs waits for it, so Codex gets one start or one resume.
        if let opening { return try await opening.value }
        let task = Task { try await self.startOrResumeThread() }
        opening = task
        defer { opening = nil }
        return try await task.value
    }

    private func startOrResumeThread() async throws -> CodexThread {
        let start = CodexThreadStart(
            folder: record.folder, model: record.model == Self.configuredModel ? nil : record.model,
            sandbox: CodexSandbox(rawValue: record.permissionMode) ?? .workspaceWrite)
        let servers = try await servers(), account = record.account?.settingsFolder
        let opened = record.hasConversation
            ? try await servers.resumeThread(account: account, identifier: record.conversationIdentifier, start)
            : try await servers.startThread(account: account, start)
        // Codex gives the identifier of its thread, which a resume needs.
        (thread, record.conversationIdentifier, record.hasConversation) = (opened, opened.identifier, true)
        Task { await self.read(opened) }
        return opened
    }

    private func read(_ opened: CodexThread) async {
        for await event in opened.events {
            emit(event)
            if case .turnEnded = event.kind {
                (isTurnRunning, record.lastActivityAt) = (false, Date())
                await sendNextMessage()
            } else {
                await changed(self)
            }
        }
        // The app-server ended, or the thread closed. A turn that ran ends with it.
        if thread?.identifier == opened.identifier { thread = nil }
        if isTurnRunning {
            isTurnRunning = false
            emit(ConversationEvent(.processEnded(ProcessEnd(exitStatus: nil, wasRequested: isClosed))))
        }
        await changed(self)
        await sendNextMessage()
    }

    /// A page of the earlier turns, which Codex keeps. The thread opens
    /// on the app-server for the read. A thread with no turn has none.
    func historyPage(cursor: String?) async throws -> CodexHistoryPage {
        guard record.hasConversation else { return CodexHistoryPage(events: [], olderCursor: nil) }
        return try await openThread().historyPage(cursor: cursor)
    }

    /// Stops the turn. The messages that waited do not go out.
    func stop() async {
        if !waitingMessages.isEmpty {
            emit(ConversationEvent(.notice(Notice(level: .information, text: "The stop removed \(waitingMessages.count) messages that waited for the agent."))))
            waitingMessages = []
        }
        if isTurnRunning { await thread?.stop() }
        await changed(self)
    }

    func answerPermission(_ request: String, allows: Bool, message: String?) async -> Bool {
        await thread?.answerPermission(identifier: request, answer: allows ? .allow : .deny) ?? false
    }

    func close() async {
        guard !isClosed else { return }
        (isClosed, waitingMessages) = (true, [])
        for listener in listeners.values { listener(.closed) }
        listeners = [:]
        await thread?.close()
    }
}
