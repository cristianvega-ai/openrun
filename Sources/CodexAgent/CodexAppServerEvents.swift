import AgentConversation

/// The events of the threads. The reader of the app-server gives them and
/// never waits for a caller.
extension CodexAppServer {
    /// Gives events to a thread. A thread with too many events that wait
    /// ends, and its caller gets an error at the end of its events.
    func emit(_ kinds: [ConversationEventKind], line: SourceLine?, to thread: String) {
        guard let state = threads[thread] else { return }
        for kind in kinds where !state.channel.add(ConversationEvent(kind, sourceLine: line)) {
            return endUnreadThread(thread)
        }
    }

    /// Ends a thread whose caller did not read its events. Codex stops its
    /// turn, and the requests of the thread end declined.
    func endUnreadThread(_ thread: String) {
        guard let state = threads.removeValue(forKey: thread) else { return }
        let text = "OpenRun closed the thread, because more than \(options.eventLimit) of its events waited to show."
        state.channel.finish(with: ConversationEvent(.notice(Notice(level: .error, text: text))))
        // A request waits for the reader, so the reader must not wait for it.
        Task {
            await endApprovals(of: { $0 == thread })
            if let turn = state.mapper.turnToStop {
                _ = try? await request("turn/interrupt", .object(["threadId": .string(thread), "turnId": .string(turn)]))
            }
            _ = try? await request("thread/unsubscribe", .object(["threadId": .string(thread)]))
        }
    }
}
