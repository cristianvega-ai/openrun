import Foundation
import SessionProtocol
import TerminalEmulation

/// The background process that owns every shell and agent.
///
/// Clients come and go: the app, the command-line tool, a script. The
/// programs in the sessions keep running between them.
public struct SessionProcess: Sendable {
    public let socketLocation: SocketLocation

    public init(socketLocation: SocketLocation) {
        self.socketLocation = socketLocation
    }

    /// Serves clients until SIGTERM, SIGINT or SIGHUP arrives. Then it ends
    /// every program, closes every client, removes the socket file, and
    /// returns.
    public func run() async throws {
        // Signal handling starts first, so a signal that arrives while the
        // socket opens is not lost.
        let signals = ShutdownSignals()
        let server = try SessionServer(location: socketLocation)
        await server.start()
        SessionServer.log("Listening on \(socketLocation.path)")

        let signal = await signals.wait()
        SessionServer.log("Received signal \(signal). Ending all sessions.")
        await server.shutDown()
        SessionServer.log("Stopped.")
    }

    /// The whole of `openrun-session`: read the options, run, and report.
    /// Returns the exit code of the process.
    public static func runFromCommandLine(arguments: [String], environment: [String: String]) async -> Int32 {
        var socketFlag: String?
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--socket":
                guard let path = remaining.popFirst() else { return usageError("--socket needs a path.") }
                socketFlag = path
            case "--help":
                guard arguments.count == 1 else { return usageError("--help takes no other arguments.") }
                print(usage)
                return 0
            default:
                return usageError("Unknown argument \(argument).")
            }
        }
        do {
            let location = try SocketLocation.resolve(flag: socketFlag, environment: environment)
            try await SessionProcess(socketLocation: location).run()
            return 0
        } catch {
            SessionServer.log("\(error)")
            return 1
        }
    }

    private static let usage = """
        Usage: openrun-session [--socket PATH]

        Runs the OpenRun session process in the foreground and logs to standard error.
        The socket is PATH, or OPENRUN_SOCKET, or ~/Library/Application Support/OpenRun/session.socket.
        A relative path starts at the current folder. The folder of the socket must belong to you,
        and other users must not be able to write to it.
        """

    private static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("openrun-session: \(PrintableText.escaping(message))\n\(usage)\n".utf8))
        return 2
    }
}
