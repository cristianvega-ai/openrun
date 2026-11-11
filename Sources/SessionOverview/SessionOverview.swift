import Foundation
import SessionConnection
import SessionProtocol

/// Everything that the session process holds, as the app last heard it on
/// the feed of the session changes (decision of 2026-11-10): the sessions,
/// the projects and the settings.
public struct SessionOverview: Equatable, Sendable {
    /// Oldest first, as the session process lists them.
    public private(set) var sessions: [SessionSummary]
    /// In the user's order. The projects whose folder this Mac does not
    /// know come last.
    public private(set) var projects: [ProjectSummary]
    public private(set) var settings: [SettingSummary]
    /// The agent threads, oldest first.
    public private(set) var threads: [ThreadSummary]

    public init(sessions: [SessionSummary] = [], projects: [ProjectSummary] = [], settings: [SettingSummary] = [], threads: [ThreadSummary] = []) {
        (self.sessions, self.projects, self.settings, self.threads) = (sessions, projects, settings, threads)
    }

    public func thread(_ identifier: UUID) -> ThreadSummary? {
        threads.first { $0.identifier == identifier }
    }

    public func session(_ identifier: UUID) -> SessionSummary? {
        sessions.first { $0.identifier == identifier }
    }

    /// The text of a setting, as `openrun settings get` prints it.
    public func settingText(named name: String) -> String? {
        settings.first { $0.name == name }?.text
    }

    /// Takes one event of the feed. The end of a connection changes
    /// nothing: the last facts stay, and the next connection starts with a
    /// new list of the sessions.
    public mutating func apply(_ event: SessionChangeReceiver.Event) {
        switch event {
        case .sessions(let list):
            sessions = list
        case .sessionChanged(let summary):
            if let index = sessions.firstIndex(where: { $0.identifier == summary.identifier }) {
                sessions[index] = summary
            } else {
                sessions.append(summary)
            }
        case .sessionEnded(let identifier):
            sessions.removeAll { $0.identifier == identifier }
        case .projects(let list):
            projects = list
        case .settings(let list):
            settings = list
        case .threads(let list):
            threads = list
        case .threadChanged(let thread):
            if let index = threads.firstIndex(where: { $0.identifier == thread.identifier }) {
                threads[index] = thread
            } else {
                threads.append(thread)
            }
        case .threadEnded(let identifier):
            threads.removeAll { $0.identifier == identifier }
        case .closed, .failed:
            break
        }
    }
}
