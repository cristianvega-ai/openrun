import AppKit
import MainWindow

/// The session process after an update of the app (milestone 7). The
/// session process of the build from before can still run, because it
/// keeps the sessions alive. Only the user decides when it ends.
extension Workspace {
    static let restartConsequence = "A restart ends every program in every session. The sessions come back as shells in their folders, "
        + "and each thread goes on with its next message."

    /// File > Restart Session Process: ends the session process after a
    /// question. The next connection starts the build of this app.
    @objc func restartSessionProcess(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Restart the session process?"
        alert.informativeText = Self.restartConsequence
        confirmRestart(alert) { [weak self] agreed in
            if agreed { self?.perform("The session process could not end") { try $0.endSessionProcess() } }
        }
    }

    /// Tells the user one time when the session process is of another
    /// build than this app, and offers the restart.
    func checkBuildOfSessionProcess() {
        guard connection.status == .connected, let running = connection.sessionProcessBuild, !knownBuilds.contains(running) else { return }
        knownBuilds.insert(running)
        let read = readBundledBuild
        // The program of the bundle prints its build, which takes a moment.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let bundled = read()
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.compareBuild(running: running, bundled: bundled) } }
        }
    }

    private func compareBuild(running: String, bundled: String?) {
        guard let bundled, bundled != running, connection.sessionProcessBuild == running else { return }
        let alert = NSAlert()
        alert.messageText = "The session process is from another build of OpenRun"
        alert.informativeText = "It still runs, so that your sessions stay alive. Restart it when your work allows. " + Self.restartConsequence
        confirmRestart(alert) { [weak self] agreed in
            if agreed { self?.perform("The session process could not end") { try $0.endSessionProcess() } }
        }
    }

    /// Shows a question about the restart. The first button keeps the
    /// sessions, so Return ends nothing.
    func askBeforeRestart(_ alert: NSAlert, then answer: @escaping (Bool) -> Void) {
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Restart")
        guard window.window.isVisible else { return answer(ModalAlert.runStandardModal(alert) == .alertSecondButtonReturn) }
        alert.beginSheetModal(for: window.window) { answer($0 == .alertSecondButtonReturn) }
    }
}
