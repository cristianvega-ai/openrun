import Foundation
import SessionLaunch
import SessionProtocol
import UntrustedText

/// The background process that owns every shell and agent.
///
/// Clients come and go: the app, the command-line tool, a script. The
/// programs in the sessions keep running between them.
public struct SessionProcess: Sendable {
    public let socketLocation: SocketLocation
    /// The Mach service of the launch agent when launchd started the
    /// process, and nil for a process that was started by hand.
    let machServiceName: String?
    /// Set for the launch agent only. A process that was started by hand
    /// runs until it gets a signal.
    let idleExit: IdleExit?
    /// The program that may receive and answer approval questions.
    let answererRequirement: AnswererRequirement

    public init(socketLocation: SocketLocation) {
        self.init(socketLocation: socketLocation, machServiceName: nil, idleExit: nil, answererRequirement: .ofThisProcess())
    }

    init(socketLocation: SocketLocation, machServiceName: String?, idleExit: IdleExit?, answererRequirement: AnswererRequirement = .ofThisProcess()) {
        self.socketLocation = socketLocation
        self.machServiceName = machServiceName
        self.idleExit = idleExit
        self.answererRequirement = answererRequirement
    }

    /// Serves clients until SIGTERM, SIGINT or SIGHUP arrives, or until the
    /// idle exit of the launch agent. Then it ends
    /// every program, closes every client, removes the socket file, and
    /// returns.
    public func run() async throws {
        // Signal handling starts first, so a signal that arrives while the
        // socket opens is not lost.
        let signals = ShutdownSignals()
        let server = try SessionServer(location: socketLocation, answererRequirement: answererRequirement)
        await server.start()
        SessionLog.write("Listening on ", detail: socketLocation.path)
        let wakeService = machServiceName.flatMap(startWakeService)

        let reason = await withTaskGroup(of: String.self) { group in
            group.addTask { "Received signal \(await signals.wait())." }
            if let idleExit {
                group.addTask {
                    // The wake service stops before the socket closes, so a
                    // later wake waits for the next process.
                    await idleExit.wait(for: server) { wakeService?.cancel() }
                    return "No session and no client for \(idleExit.timeLimit)."
                }
            }
            let first = await group.next() ?? "Stopped."
            group.cancelAll()
            return first
        }
        SessionLog.write("\(reason) Ending all sessions.")
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
        var answererRequirement = AnswererRequirement.ofThisProcess()
        var isLaunchAgent = false
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--socket":
                guard let path = remaining.popFirst() else { return usageError("--socket needs a path.") }
                socketFlag = path
            case "--answerer-requirement":
                guard let text = remaining.popFirst() else { return usageError("--answerer-requirement needs a code requirement.") }
                answererRequirement = AnswererRequirement(text: text)
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
            let idleExit = isLaunchAgent ? IdleExit(environment: environment) : nil
            try await SessionProcess(socketLocation: location, machServiceName: machServiceName, idleExit: idleExit, answererRequirement: answererRequirement).run()
            return 0
        } catch {
            SessionLog.write("", detail: "\(error)")
            return 1
        }
    }

    private static let usage = """
        Usage: openrun-session [--socket PATH] [--answerer-requirement REQUIREMENT] [--launch-agent]

        Runs the OpenRun session process in the foreground and logs to standard error.
        The socket is PATH, or OPENRUN_SOCKET, or ~/Library/Application Support/OpenRun/session.socket.
        A relative path starts at the current folder. The folder of the socket must belong to you,
        and other users must not be able to write to it.
        launchd gives --launch-agent: the process then answers wake requests, and it
        ends after 30 seconds with no session and no client.
        Only a program that meets REQUIREMENT, in the code requirement language, receives
        and answers approval questions. The default is OpenRun.app of the team of this program.
        """

    private static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("openrun-session: \(PrintableText.escaping(message))\n\(usage)\n".utf8))
        return 2
    }
}
