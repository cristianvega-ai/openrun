import Foundation
import PseudoTerminal
import SessionProtocol

/// What the app asks the session process to start for a new row of the
/// sessions list (decision of 2026-11-10).
struct NewSessionLaunch: Equatable {
    /// The folder of the selected project, or the home folder.
    var folder: String
    /// The program and its arguments. `nil` starts the login shell.
    var command: [String]?

    /// - Parameter commandLine: The command line of a new-session command
    ///   of the settings, such as `claude`. An empty one starts the login
    ///   shell itself.
    init(commandLine: String, folder: String, shell: LoginShell = .current()) {
        self.folder = folder
        // An app that Finder started has a short `PATH`, and the agents
        // live in folders that the shell of the user adds. An interactive
        // login shell reads the same files as a terminal window. `exec`
        // puts the command in the place of the shell, so the session ends
        // with the command.
        command = commandLine.isEmpty ? nil : [shell.path, "-l", "-i", "-c", "exec " + commandLine]
    }

    /// The request for the session process. The new session gets the
    /// environment of the app, as a program in any terminal gets the
    /// environment of the terminal (decision of 2026-10-24).
    func request(size: SessionSize, environment: [String: String] = ProcessInfo.processInfo.environment) -> ClientMessage {
        .createSession(folder: folder, command: command, size: size, environment: environment)
    }
}
