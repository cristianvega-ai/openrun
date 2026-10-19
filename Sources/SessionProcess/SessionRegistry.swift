import Foundation
import PseudoTerminal
import SessionProtocol

/// The sessions that exist, found by identifier.
actor SessionRegistry {
    private var sessions: [UUID: Session] = [:]
    private let socketPath: String
    /// Set before `terminateAll` first suspends. A client that is already
    /// connected can still send `createSession` while the programs end, and
    /// that program would outlive the session process.
    private var isStopping = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Starts a session and adds it to the list.
    func create(folder: String, command: [String]?, size: SessionSize, environment: [String: String]) async throws -> SessionSummary {
        let identifier = UUID()
        var programEnvironment = environment
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
        let session = try Session(summary: summary, launch: launch) { [self] identifier in
            await remove(identifier)
        }
        sessions[identifier] = session
        await session.start()
        return summary
    }

    func session(for identifier: UUID) -> Session? {
        sessions[identifier]
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
        sessions[identifier] = nil
    }
}
