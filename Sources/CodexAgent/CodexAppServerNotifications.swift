import AgentConversation

/// The lines that the app-server starts: notifications, its requests, and
/// lines that OpenRun cannot read.
extension CodexAppServer {
    func receive(_ incoming: CodexMessageReader.Incoming) async {
        switch incoming {
        case .message(.notification(let method, let parameters), let line):
            await notification(method, parameters, line: line)
        case .message(.request(let identifier, let method, let parameters), let line):
            await serverRequest(identifier, method: method, parameters: parameters, line: line)
        case .message:
            // An answer after its time limit, or the refusal of a line that
            // Codex could not read. No caller waits for it.
            break
        case .unreadable(let unknown, let line):
            for thread in threads.keys { emit([.unknown(unknown)], line: line, to: thread) }
        }
    }

    func notification(_ method: String, _ parameters: JSONValue, line: SourceLine) async {
        guard let thread = Self.threadIdentifier(of: parameters) else {
            for identifier in threads.keys { await deliver(method, parameters, line: line, to: identifier) }
            return
        }
        if threads[thread] != nil {
            if method == "serverRequest/resolved" { await approvalResolved(parameters, thread: thread) }
            await deliver(method, parameters, line: line, to: thread)
            if method == "item/started", let item = parameters["item"]?["id"]?.string { await showApprovals(of: item, line: line) }
        } else if unsubscribingThreads[thread] == nil {
            // A thread whose start or resume has not returned. A line of a
            // thread that closed is dropped.
            earlyLines.append((thread, method, parameters, line))
            if earlyLines.count > Self.earlyLineLimit { earlyLines.removeFirst() }
        }
    }

    /// Maps a notification with the mapper of the thread. A method that
    /// the mapper does not know gives an unknown event with the line.
    func deliver(_ method: String, _ parameters: JSONValue, line: SourceLine, to thread: String) async {
        guard threads[thread] != nil else { return }
        let kinds = threads[thread]?.mapper.events(method: method, parameters: parameters)
            ?? [.unknown(UnknownLine(reason: .unknownKind, kind: method, text: line.text, byteCount: line.byteCount))]
        emit(kinds, line: line, to: thread)
    }

    /// Opens a thread with its first events, then gives it the lines that
    /// came before its answer.
    func open(_ thread: String, first: [ConversationEventKind]) async -> CodexEventChannel {
        let state = threads[thread] ?? CodexThreadState(channel: CodexEventChannel(limit: options.eventLimit, byteLimit: options.eventByteLimit))
        threads[thread] = state
        emit(first, line: nil, to: thread)
        let early = earlyLines.filter { $0.thread == thread }
        earlyLines.removeAll { $0.thread == thread }
        for line in early { await deliver(line.method, line.parameters, line: line.line, to: thread) }
        return state.channel
    }

    static func threadIdentifier(of parameters: JSONValue) -> String? {
        parameters["threadId"]?.string ?? parameters["thread"]?["id"]?.string
    }

    /// Sends an approval to its thread. OpenRun refuses any other request
    /// of the app-server, so that Codex does not wait for an answer, and
    /// the thread learns of it.
    func serverRequest(_ identifier: CodexRequestIdentifier, method: String, parameters: JSONValue, line: SourceLine) async {
        if method == CodexApproval.commandMethod || method == CodexApproval.fileChangeMethod {
            return await approvalRequested(identifier, method: method, parameters: parameters, line: line)
        }
        if let refusal = try? CodexOutgoingLine.failure(to: identifier, code: -32601, message: "OpenRun does not support \(method).") {
            await connection.send(refusal)
        }
        let text = "Codex asked for \(method), which OpenRun does not support, so OpenRun refused it."
        if let thread = Self.threadIdentifier(of: parameters) {
            emit([.notice(Notice(level: .warning, text: text))], line: line, to: thread)
        }
    }
}
