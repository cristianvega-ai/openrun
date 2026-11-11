import Foundation
import SessionProtocol
import Synchronization

/// The newest summary of each session, and the connections that watch them
/// (`receiveSessionChanges`, decision of 2026-11-10).
///
/// Each session hands its summary here from its own context, and the feed
/// sends it to every watcher under one lock. So a watcher gets the present
/// list and then each later change, with no gap and no repeat, and the end
/// of a session after its last change. A send only queues the message, so
/// the lock is never held for a slow watcher. A watcher that falls behind
/// follows the rules of every client (see `ConnectionLimits`).
final class SessionChangeFeed: Sendable {
    typealias Send = @Sendable (ServerMessage) -> Void

    private struct State {
        var summaries: [UUID: SessionSummary] = [:]
        var watchers: [ObjectIdentifier: Send] = [:]
    }

    private let state = Mutex(State())

    /// Adds a session that has started.
    func add(_ summary: SessionSummary) {
        state.withLock { state in
            state.summaries[summary.identifier] = summary
            for send in state.watchers.values { send(.sessionChanged(summary)) }
        }
    }

    /// Sends the new summary of a session. A summary that did not change,
    /// or one of a session that has ended, is dropped.
    func change(_ summary: SessionSummary) {
        state.withLock { state in
            guard let known = state.summaries[summary.identifier], known != summary else { return }
            state.summaries[summary.identifier] = summary
            for send in state.watchers.values { send(.sessionChanged(summary)) }
        }
    }

    /// The session has ended. Nothing of it is sent after this.
    func end(_ identifier: UUID) {
        state.withLock { state in
            guard state.summaries.removeValue(forKey: identifier) != nil else { return }
            for send in state.watchers.values { send(.sessionEnded(identifier: identifier)) }
        }
    }

    /// Sends the present list, oldest first, and then each change.
    func addWatcher(_ key: ObjectIdentifier, send: @escaping Send) {
        state.withLock { state in
            send(.sessionList(state.summaries.values.sorted { $0.createdAt < $1.createdAt }))
            state.watchers[key] = send
        }
    }

    func removeWatcher(_ key: ObjectIdentifier) {
        _ = state.withLock { $0.watchers.removeValue(forKey: key) }
    }
}
