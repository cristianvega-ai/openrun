import Foundation
import Projects
import PseudoTerminal
import SessionProtocol

/// The sessions that exist, found by identifier.
actor SessionRegistry {
    private var sessions: [UUID: Session] = [:]
    private let socketPath: String
    private let helperSearchPath: HelperSearchPath
    private let changes: SessionChangeFeed?
    /// The most sessions at once when the setting `session-limit` names no
    /// other (decision of 2026-11-10). An agent can start sessions by
    /// itself, and a loop must not start them without end.
    static let defaultSessionLimit = 100
    private var sessionLimit: Int
    /// The first line of a session that came back after a restart.
    static let restoredNotice = "[OpenRun started this session again after a restart. The text from before is gone.]"
    /// The line limit of the scrollback of each new session. A session
    /// keeps the limit that it started with.
    private var scrollbackLimit: Int
    /// The version of the settings that gave the two limits.
    private var limitsVersion = 0
    /// Set before `terminateAll` first suspends. A client that is already
    /// connected can still send `createSession` while the programs end, and
    /// that program would outlive the session process.
    private var isStopping = false
    /// The terminal sessions of the sessions that ended, while a process of
    /// them can still live, such as a job that the program left behind.
    private var endedTerminalSessions: Set<pid_t> = []
    /// The newest list of the projects that the keeper gave, and its version.
    private var projects: ProjectList
    private var projectsVersion = 0
    /// The folder that each session started in, with its symbolic links
    /// resolved once, at the start. The system gives the real path of a
    /// folder, and so does the list of the projects.
    private var startFolders: [UUID: String] = [:]

    init(
        socketPath: String, helperSearchPath: HelperSearchPath, changes: SessionChangeFeed? = nil, projects: ProjectList = ProjectList(),
        sessionLimit: Int = defaultSessionLimit, scrollbackLimit: Int = Session.scrollbackLimit
    ) {
        self.scrollbackLimit = scrollbackLimit
        self.projects = projects
        self.sessionLimit = sessionLimit
        self.socketPath = socketPath
        self.helperSearchPath = helperSearchPath
        self.changes = changes
    }

    /// Starts a session and adds it to the list.
    ///
    /// - Parameter kept: The identifier, the name and the age of a session
    ///   of the last run of the session process, which comes back.
    func create(
        folder: String, command: [String]?, size: SessionSize, environment: [String: String],
        restoring kept: (identifier: UUID, name: String?, createdAt: Date)? = nil
    ) async throws -> SessionSummary {
        // This check must come before the first suspension point. The program
        // starts in `Session.init`, and the list `terminateAll` ends is
        // already fixed by then.
        guard !isStopping else { throw SessionProcessError.stopping }
        // The session joins the list before the first suspension point, so
        // two requests at once cannot both pass the limit.
        guard sessions.count < sessionLimit else { throw SessionProcessError.sessionLimitReached(limit: sessionLimit) }
        let identifier = kept?.identifier ?? UUID()
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

        var summary = SessionSummary(identifier: identifier, folder: folder, command: shownCommand, size: size, createdAt: kept?.createdAt ?? Date())
        summary.name = kept?.name
        let startFolder = Self.realPath(of: folder)
        summary.projectIdentifier = projects.project(holding: startFolder)?.identifier
        // A session that comes back has no text from before, and the line tells why.
        let notice = kept == nil ? nil : Self.restoredNotice
        let session = try Session(summary: summary, launch: launch, changes: changes, scrollbackLimit: scrollbackLimit, openingNotice: notice) { [self] identifier in
            await remove(identifier)
        }
        sessions[identifier] = session
        startFolders[identifier] = startFolder
        await session.start()
        return await session.summary
    }

    var isEmpty: Bool { sessions.isEmpty }

    /// Takes the limits of newer settings. The limit of sessions applies to
    /// the next `create`, and the sessions that run stay. The scrollback
    /// limit applies to the sessions that start after it.
    func updateLimits(sessionLimit: Int, scrollbackLimit: Int, version: Int) {
        guard version > limitsVersion else { return }
        (self.sessionLimit, self.scrollbackLimit, limitsVersion) = (sessionLimit, scrollbackLimit, version)
    }

    /// The path with its symbolic links resolved, or the path itself when
    /// the system cannot resolve it.
    private static func realPath(of folder: String) -> String {
        guard let resolved = realpath(folder, nil) else { return folder }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Takes a newer list of the projects, and gives each session the
    /// project that its start folder belongs to now. A session whose
    /// project changed tells its watchers. An older list is ignored, so the
    /// order in which the lists arrive does not matter.
    func updateProjects(_ list: ProjectList, version: Int) async {
        guard version > projectsVersion else { return }
        (projects, projectsVersion) = (list, version)
        for (identifier, session) in sessions {
            // A newer list can come while this one waits for a session, so
            // each session gets the project of the newest list.
            let project = startFolders[identifier].flatMap { projects.project(holding: $0)?.identifier }
            _ = await session.update { $0.projectIdentifier = project }
        }
    }

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
        startFolders[identifier] = nil
        endedTerminalSessions.insert(session.programProcessIdentifier)
        forgetFreeTerminalSessions()
    }
}
