import Foundation
import SessionLaunch
import SessionProtocol
import TerminalEmulation

/// The background process that owns every shell and agent.
///
/// Clients come and go: the app, the command-line tool, a script. The
/// programs in the sessions keep running between them.
public struct SessionProcess: Sendable {
    public let socketLocation: SocketLocation
    /// The Mach service of the launch agent when launchd started the
    /// process, and nil for a process that was started by hand.
    let machServiceName: String?

    public init(socketLocation: SocketLocation) {
        self.init(socketLocation: socketLocation, machServiceName: nil)
    }

    init(socketLocation: SocketLocation, machServiceName: String?) {
        self.socketLocation = socketLocation
        self.machServiceName = machServiceName
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
        SessionLog.write("Listening on ", detail: socketLocation.path)
        let wakeService = machServiceName.flatMap(startWakeService)

        let signal = await signals.wait()
        SessionLog.write("Received signal \(signal). Ending all sessions.")
        wakeService?.cancel()
        await server.shutDown()
        SessionLog.write("Stopped.")
    }

    /// The service starts after the socket listens, because a client that
    /// gets the answer connects at once. Without it, the socket still
    /// serves the clients that find it.
    private func startWakeService(named name: String) -> SessionWakeService? {
        do {
            let service = try SessionWakeService(socketPath: socketLocation.path, machServiceName: name)
            SessionLog.write("Answering wake requests as the launch agent.")
            return service
        } catch {
            SessionLog.write("The wake service did not start, and the socket still serves clients: ", detail: "\(error)")
            return nil
        }
    }

    /// The whole of `openrun-session`: read the options, run, and report.
    /// Returns the exit code of the process.
    public static func runFromCommandLine(arguments: [String], environment: [String: String]) async -> Int32 {
        var socketFlag: String?
        var isLaunchAgent = false
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--socket":
                guard let path = remaining.popFirst() else { return usageError("--socket needs a path.") }
                socketFlag = path
            case LaunchAgentNames.launchAgentFlag:
                isLaunchAgent = true
            case "--help":
                guard arguments.count == 1 else { return usageError("--help takes no other arguments.") }
                print(usage)
                return 0
            default:
                return usageError("Unknown argument \(argument).")
            }
        }
        do {
            // Clients wake the launch agent only for the default socket, so
            // it does not take OPENRUN_SOCKET from the environment.
            let location = try SocketLocation.resolve(flag: socketFlag, environment: isLaunchAgent ? [:] : environment)
            let machServiceName = isLaunchAgent ? LaunchAgentNames.machServiceName(in: environment) : nil
            try await SessionProcess(socketLocation: location, machServiceName: machServiceName).run()
            return 0
        } catch {
            SessionLog.write("", detail: "\(error)")
            return 1
        }
    }

    private static let usage = """
        Usage: openrun-session [--socket PATH] [--launch-agent]

        Runs the OpenRun session process in the foreground and logs to standard error.
        The socket is PATH, or OPENRUN_SOCKET, or ~/Library/Application Support/OpenRun/session.socket.
        A relative path starts at the current folder. The folder of the socket must belong to you,
        and other users must not be able to write to it.
        launchd gives --launch-agent: the process then answers wake requests.
        """

    private static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("openrun-session: \(PrintableText.escaping(message))\n\(usage)\n".utf8))
        return 2
    }
}
