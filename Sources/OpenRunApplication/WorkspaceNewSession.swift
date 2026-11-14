import AppKit
import ProjectsList
import SessionConnection
import SessionProtocol
import TerminalView

/// The start and the end of sessions from the window.
extension Workspace {
    /// Starts a session in the folder of the selected project, or in the
    /// home folder, and selects its row (decision of 2026-11-10).
    ///
    /// - Parameter name: The shown name of a new-session command of the
    ///   settings. `nil`, or a name that the settings do not hold, starts
    ///   the login shell.
    func newSession(commandNamed name: String? = nil) {
        newSession(commandLine: settings.newSessionCommands.first { $0.name == name }?.commandLine ?? "")
    }

    /// - Parameters:
    ///   - commandLine: The command for the login shell. An empty one starts the login shell itself.
    ///   - rowName: The name of the new row, or `nil` for the name that its program gives.
    func newSession(commandLine: String, rowName: String? = nil) {
        let launch = NewSessionLaunch(commandLine: commandLine, folder: selectedProjectFolder ?? home, shell: loginShell)
        // The session starts with the grid of the third pane, so its
        // program draws once for the right size.
        let grid = TerminalView.estimatedGrid(for: window.contentAreaSize, scale: window.window.backingScaleFactor)
        let request = launch.request(size: SessionSize(columns: grid.columns, rows: grid.rows), environment: sessionEnvironment)
        requests.perform({ client in
            guard case .sessionCreated(let summary) = try client.request(request) else {
                throw SessionConnectionError.unexpectedAnswer(request: "new session")
            }
            return summary.identifier
        }, then: { [weak self] result in
            switch result {
            case .success(let identifier):
                self?.select(newSession: identifier)
                if let rowName { self?.perform("The terminal could not get its name") { try $0.rename(session: identifier, to: rowName) } }
            case .failure(let failure): self?.showFailure("The session could not start", failure.message)
            }
        })
    }

    var selectedProjectFolder: String? {
        guard case .project(let identifier) = window.projectsList.selection else { return nil }
        return connection.overview.projects.first { $0.identifier == identifier }?.folder
    }

    /// The row of the session takes the selection and the keyboard focus,
    /// now or when the feed brings the session.
    func select(newSession identifier: UUID) {
        sessionToSelect = identifier
        if let row = layout.row(showing: identifier) { layout.selectedRow = row.identifier }
        refresh()
    }

    /// Ends the sessions of a row. It asks first when a program other than
    /// a shell at its prompt runs in one of them.
    func closeRow(_ identifier: UUID) {
        guard let row = layout.row(identifier) else { return }
        if row.pane.leaves.count == 1, let thread = row.pane.leadingThread { return closeThread(thread) }
        // A row with splits ends each of its sessions and closes each of its threads.
        for thread in row.pane.threads { closeThread(thread) }
        let sessions = row.pane.sessions.compactMap { connection.overview.session($0) }
        let end = { [weak self] in
            for session in sessions {
                self?.perform("The session could not close") { _ = try $0.request(.killSession(identifier: session.identifier)) }
            }
        }
        guard let question = sessions.lazy.compactMap(CloseQuestion.init(session:)).first else { return end() }
        confirmClose(question) { agreed in
            if agreed { end() }
        }
    }

    /// Sends a request whose answer shows nothing, and shows its failure.
    func perform(_ failureTitle: String, _ request: @escaping @Sendable (SessionClient) throws -> Void) {
        requests.perform(request) { [weak self] result in
            if case .failure(let failure) = result { self?.showFailure(failureTitle, failure.message) }
        }
    }
}
