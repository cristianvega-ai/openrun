import Foundation
import SessionConnection
import SessionProtocol

/// What a window shows: a new session, or a session that runs.
public enum SessionStart: Equatable, Sendable {
    /// A new session that runs the login shell of the user in `folder`. The
    /// shell gets `environment`, as a program in any terminal gets the
    /// environment of the terminal (decision of 2026-10-24).
    case newSession(folder: String, environment: [String: String])
    /// A session that runs, found by its identifier.
    case runningSession(UUID)

    /// Command-N: the home folder, with the environment of the app. The login
    /// shell reads its own start files, so it sets the `PATH` of the user also
    /// when the app has the small environment of launchd.
    public static func newSessionInHomeFolder() -> SessionStart {
        .newSession(folder: NSHomeDirectory(), environment: ProcessInfo.processInfo.environment)
    }

    /// Connects, creates the session when it is new, and attaches with `size`.
    ///
    /// It blocks, and the first connection can wake the launch agent and wait
    /// for it, so it never runs on the main thread. The window asks for size
    /// changes. It relays no raw output, so the session process answers the
    /// queries of the program.
    func attach(at location: SocketLocation, size: SessionSize) throws -> StartedSession {
        let client = try SessionClient(location: location)
        let summary: SessionSummary
        switch self {
        case .newSession(let folder, let environment):
            let request = ClientMessage.createSession(folder: folder, command: nil, size: size, environment: environment)
            guard case .sessionCreated(let created) = try client.request(request) else {
                throw SessionConnectionError.unexpectedAnswer(request: "new session")
            }
            summary = created
        case .runningSession(let identifier):
            summary = try client.session(matching: SessionSummary.text(for: identifier))
        }
        let attachment = try client.attach(to: summary.identifier, size: size, relaysRawOutput: false, receivesSizeChanges: true)
        return StartedSession(summary: summary, attachment: attachment)
    }
}

/// A session that a window attached to. The attachment holds the snapshot.
struct StartedSession: Sendable {
    let summary: SessionSummary
    let attachment: any AttachedSession
}
