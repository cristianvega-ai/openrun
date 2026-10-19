import Foundation
import SessionProtocol

/// `openrun new`: starts a session and prints its identifier.
struct NewCommand {
    var folder: String?
    var program: [String]

    func run(location: SocketLocation, environment: [String: String]) throws -> String {
        let client = try SessionClient(location: location)
        // The session process may run in another folder than this command, so
        // it gets an absolute path.
        let current = FileManager.default.currentDirectoryPath
        let absoluteFolder = URL(fileURLWithPath: folder ?? current, relativeTo: URL(fileURLWithPath: current, isDirectory: true)).standardizedFileURL.path
        // A program starts with the environment of the person who asked for
        // it, such as their PATH and the account settings of their agents.
        let answer = try client.request(.createSession(
            folder: absoluteFolder,
            command: program.isEmpty ? nil : program,
            size: RawTerminalMode.windowSize(of: STDOUT_FILENO) ?? SessionSize(columns: 80, rows: 24),
            environment: environment
        ))
        guard case .sessionCreated(let summary) = answer else {
            throw CommandLineToolError.failure("The session process gave an unexpected answer to the new request.")
        }
        return summary.identifierText + "\n"
    }
}
