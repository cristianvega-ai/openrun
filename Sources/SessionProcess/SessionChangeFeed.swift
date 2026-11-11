import Foundation
import SessionProtocol
import Synchronization

/// The newest summary of each session, the projects and the settings, and
/// the connections that watch them (`receiveSessionChanges`, decision of
/// 2026-11-10).
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
        /// Nil until the keeper of the projects gives its first list.
        var projects: [ProjectSummary]?
        /// Nil until the keeper of the settings gives its first list.
        var settings: [SettingSummary]?
        /// Nil until the registry of the threads gives its first list.
        /// Oldest first.
        var threads: [ThreadSummary]?
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

    /// Keeps the new list of the projects and sends it to every watcher.
    func replaceProjects(_ projects: [ProjectSummary]) {
        state.withLock { state in
            state.projects = projects
            for send in state.watchers.values { send(.projectList(projects)) }
        }
    }

    /// Keeps the new list of the settings and sends it to every watcher.
    func replaceSettings(_ settings: [SettingSummary]) {
        state.withLock { state in
            state.settings = settings
            for send in state.watchers.values { send(.settingList(settings)) }
        }
    }

    /// Keeps the list of the threads at the start of the session process.
    func replaceThreads(_ threads: [ThreadSummary]) {
        state.withLock { $0.threads = threads }
    }

    /// Keeps a new thread, or the new facts of a thread, and tells every watcher.
    func threadChanged(_ summary: ThreadSummary) {
        state.withLock { state in
            if let index = state.threads?.firstIndex(where: { $0.identifier == summary.identifier }) {
                state.threads?[index] = summary
            } else {
                state.threads = (state.threads ?? []) + [summary]
            }
            for send in state.watchers.values { send(.threadChanged(summary)) }
        }
    }

    func threadEnded(_ identifier: UUID) {
        state.withLock { state in
            state.threads?.removeAll { $0.identifier == identifier }
            for send in state.watchers.values { send(.threadEnded(identifier: identifier)) }
        }
    }

    /// Sends the present list, oldest first, then the projects and the
    /// settings, and then each change of any of them, in the order of the
    /// changes (decision of 2026-11-10).
    func addWatcher(_ key: ObjectIdentifier, send: @escaping Send) {
        state.withLock { state in
            send(.sessionList(state.summaries.values.sorted { $0.createdAt < $1.createdAt }))
            if let projects = state.projects { send(.projectList(projects)) }
            if let settings = state.settings { send(.settingList(settings)) }
            if let threads = state.threads { send(.threadList(threads)) }
            state.watchers[key] = send
        }
    }

    func removeWatcher(_ key: ObjectIdentifier) {
        _ = state.withLock { $0.watchers.removeValue(forKey: key) }
    }
}
