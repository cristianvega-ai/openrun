import SessionProtocol

/// How the keeper of the session records hears of the sessions.
extension SessionRecordKeeper {
    /// Follows the feed of the session changes as a watcher does, in the
    /// order of the changes.
    nonisolated func follow(_ feed: SessionChangeFeed) {
        let (messages, continuation) = AsyncStream.makeStream(of: ServerMessage.self)
        feed.addWatcher(ObjectIdentifier(self)) { continuation.yield($0) }
        Task { for await message in messages { await self.take(message) } }
    }

    private func take(_ message: ServerMessage) {
        switch message {
        case .sessionList(let list): list.forEach(keep)
        case .sessionChanged(let summary): keep(summary)
        case .sessionEnded(let identifier): forget(identifier)
        default: break
        }
    }
}
