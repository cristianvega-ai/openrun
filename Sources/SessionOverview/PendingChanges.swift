import Foundation
import SessionConnection
import Synchronization

/// The events of the feed that wait for the main thread.
///
/// A busy session sends a change four times a second, and one hundred
/// sessions can do so together. The main thread takes every event that
/// waits in one step. A newer change of a session replaces the one that
/// waits, and a newer list replaces the older one, so a main thread that
/// is slow never makes this list long.
final class PendingChanges: Sendable {
    private struct State {
        var events: [SessionChangeReceiver.Event] = []
        /// Where the change of each session waits.
        var sessionPlaces: [UUID: Int] = [:]
        var threadPlaces: [UUID: Int] = [:]
        var projectsPlace: Int?
        var settingsPlace: Int?
    }

    private let state = Mutex(State())

    /// Adds an event behind the ones that wait.
    ///
    /// - Returns: Whether no event waited before, so the caller wakes the
    ///   main thread once for each batch.
    func add(_ event: SessionChangeReceiver.Event) -> Bool {
        state.withLock { state in
            let place: Int?
            switch event {
            case .sessionChanged(let summary): place = state.sessionPlaces[summary.identifier]
            case .threadChanged(let thread): place = state.threadPlaces[thread.identifier]
            case .projects: place = state.projectsPlace
            case .settings: place = state.settingsPlace
            default: place = nil
            }
            if let place {
                state.events[place] = event
                return false
            }
            switch event {
            case .sessionChanged(let summary): state.sessionPlaces[summary.identifier] = state.events.count
            case .threadChanged(let thread): state.threadPlaces[thread.identifier] = state.events.count
            case .projects: state.projectsPlace = state.events.count
            case .settings: state.settingsPlace = state.events.count
            // A change that waits is older than a new list or an end, so
            // a later change must come after them.
            case .sessions: state.sessionPlaces = [:]
            case .threads: state.threadPlaces = [:]
            case .sessionEnded(let identifier): state.sessionPlaces[identifier] = nil
            case .threadEnded(let identifier): state.threadPlaces[identifier] = nil
            case .closed, .failed: break
            }
            state.events.append(event)
            return state.events.count == 1
        }
    }

    /// Gives every event that waits, in order, and starts an empty batch.
    func takeAll() -> [SessionChangeReceiver.Event] {
        state.withLock { state in
            defer { state = State() }
            return state.events
        }
    }
}
