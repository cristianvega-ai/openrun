import Foundation
import PseudoTerminal
import SessionProtocol

/// The sessions that exist, found by identifier.
actor SessionRegistry {
    private var sessions: [UUID: Session] = [:]
    private let socketPath: String
    private let helperSearchPath: HelperSearchPath
    private let changes: SessionChangeFeed?
    /// The most sessions at once (decision of 2026-11-10). An agent can
    /// start sessions by itself, and a loop must not start them without end.
    static let defaultSessionLimit = 100
    private let sessionLimit: Int
    /// Set before `terminateAll` first suspends. A client that is already
    /// connected can still send `createSession` while the programs end, and
    /// that program would outlive the session process.
    private var isStopping = false
    /// The terminal sessions of the sessions that ended, while a process of
    /// them can still live, such as a job that the program left behind.
    private var endedTerminalSessions: Set<pid_t> = []

    init(socketPath: String, helperSearchPath: HelperSearchPath, changes: SessionChangeFeed? = nil, sessionLimit: Int = defaultSessionLimit) {
        self.sessionLimit = sessionLimit
        self.socketPath = socketPath
        self.helperSearchPath = helperSearchPath
        self.changes = changes
    }

    /// Starts a session and adds it to the list.
    func create(folder: String, command: [String]?, size: SessionSize, environment: [String: String]) async throws -> SessionSummary {
        // This check must come before the first suspension point. The program
        // starts in `Session.init`, and the list `terminateAll` ends is
        // already fixed by then.
        guard !isStopping else { throw SessionProcessError.stopping }
        // The session joins the list before the first suspension point, so
        // two requests at once cannot both pass the limit.
        guard sessions.count < sessionLimit else { throw SessionProcessError.sessionLimitReached(limit: sessionLimit) }
        let identifier = UUID()
        var programEnvironment = helperSearchPath.adding(to: environment)
        programEnvironment.merge(
            SessionEnvironment.variables(sessionIdentifier: identifier, socketPath: socketPath),
            uniquingKeysWith: { _, ours in ours }
        )
        let terminalSize = PseudoTerminalSize(columns: size.columns, rows: size.rows)

        let launch: ProgramLaunch
        let shownCommand: [String]
        if let command, let program = command.first {
            launch = ProgramLaunch(
                executablePath: program,
                arguments: Array(command.dropFirst()),
                folder: folder,
                environment: programEnvironment,
                size: terminalSize
            )
            shownCommand = command
        } else {
            let shell = LoginShell.current()
            launch = shell.launch(folder: folder, environment: programEnvironment, size: terminalSize)
            shownCommand = [shell.path]
        }

        let summary = SessionSummary(identifier: identifier, folder: folder, command: shownCommand, size: size, createdAt: Date())
        let session = try Session(summary: summary, launch: launch, changes: changes) { [self] identifier in
            await remove(identifier)
        }
        sessions[identifier] = session
        await session.start()
        return await session.summary
    }

    var isEmpty: Bool { sessions.isEmpty }

    func session(for identifier: UUID) -> Session? {
        sessions[identifier]
    }

    /// The session that a caller runs in. A process of a session has the
    /// terminal session of its program, unless it started one of its own. A
    /// process of a session that has ended could have come from any session.
    func place(of peer: PeerProcess) -> CallerPlace {
        guard let terminalSession = peer.terminalSessionIdentifier else { return .unknown }
        if let match = sessions.first(where: { $0.value.programProcessIdentifier == terminalSession }) {
            return .session(match.key)
        }
        forgetFreeTerminalSessions()
        return endedTerminalSessions.contains(terminalSession) ? .unknown : .outsideEverySession
    }

    /// A number with no live process can go to a new session, so it is
    /// forgotten. When the processes cannot be listed, every number stays.
    private func forgetFreeTerminalSessions() {
        guard let live = TerminalSessionCensus.liveSessions(among: endedTerminalSessions) else { return }
        endedTerminalSessions.formIntersection(live)
    }

    /// The summaries of all sessions, oldest first.
    func summaries() async -> [SessionSummary] {
        var all: [SessionSummary] = []
        for session in sessions.values { all.append(await session.summary) }
        return all.sorted { $0.createdAt < $1.createdAt }
    }

    /// Ends every program and waits until all sessions are gone.
    func terminateAll() async {
        isStopping = true
        let all = Array(sessions.values)
        await withTaskGroup(of: Void.self) { group in
            for session in all { group.addTask { await session.terminate() } }
        }
    }

    private func remove(_ identifier: UUID) {
        guard let session = sessions.removeValue(forKey: identifier) else { return }
        endedTerminalSessions.insert(session.programProcessIdentifier)
        forgetFreeTerminalSessions()
    }
}
