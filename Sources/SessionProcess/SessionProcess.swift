import DataStorage
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
    /// Where the projects and the settings are. Only this process writes there.
    let dataFolder: DataFolder
    /// How the agents of the threads start.
    let agentOptions: AgentLaunchProvider.Options

    public init(socketLocation: SocketLocation) {
        self.init(socketLocation: socketLocation, machServiceName: nil, idleExit: nil, answererRequirement: .ofThisProcess())
    }

    init(
        socketLocation: SocketLocation, dataFolder: DataFolder? = nil, machServiceName: String?, idleExit: IdleExit?,
        answererRequirement: AnswererRequirement = .ofThisProcess(), agentOptions: AgentLaunchProvider.Options = AgentLaunchProvider.Options()
    ) {
        self.agentOptions = agentOptions
        self.socketLocation = socketLocation
        self.dataFolder = dataFolder ?? DataFolder(path: socketLocation.folder)
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
        let server = try SessionServer(location: socketLocation, dataFolder: dataFolder, answererRequirement: answererRequirement, agentOptions: agentOptions)
        await server.restoreSessions()
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
            group.addTask {
                await server.waitForEndRequest()
                return "OpenRun.app asked the session process to end."
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
        var dataFolderFlag: String?
        var answererRequirement = AnswererRequirement.ofThisProcess()
        var isLaunchAgent = false
        var agentOptions = AgentLaunchProvider.Options()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--socket":
                guard let path = remaining.popFirst() else { return usageError("--socket needs a path.") }
                socketFlag = path
            case "--data-folder":
                guard let path = remaining.popFirst() else { return usageError("--data-folder needs a path.") }
                dataFolderFlag = path
            case "--agent-program":
                guard let program = remaining.popFirst(), !program.isEmpty else { return usageError("--agent-program needs a program.") }
                agentOptions.program = program
            case "--codex-program":
                guard let program = remaining.popFirst(), !program.isEmpty else { return usageError("--codex-program needs a program.") }
                agentOptions.codexProgram = program
            case "--own-environment-for-agents":
                agentOptions.usesOwnEnvironment = true
            case "--answerer-requirement":
                guard let text = remaining.popFirst() else { return usageError("--answerer-requirement needs a code requirement.") }
                answererRequirement = AnswererRequirement(text: text)
            case LaunchAgentNames.launchAgentFlag:
                isLaunchAgent = true
            case "--help":
                guard arguments.count == 1 else { return usageError("--help takes no other arguments.") }
                print(usage)
                return 0
            case "--build-identifier":
                guard arguments.count == 1 else { return usageError("--build-identifier takes no other arguments.") }
                print(BuildIdentifier.current ?? "")
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
            let dataFolder = dataFolderFlag.map { Self.dataFolder(flag: $0, currentFolder: FileManager.default.currentDirectoryPath) }
            try await SessionProcess(
                socketLocation: location, dataFolder: dataFolder, machServiceName: machServiceName, idleExit: idleExit,
                answererRequirement: answererRequirement, agentOptions: agentOptions
            ).run()
            return 0
        } catch {
            SessionLog.write("", detail: "\(error)")
            return 1
        }
    }

    /// The folder that `--data-folder` names. A relative path starts at the
    /// current folder, as the path of the socket does.
    static func dataFolder(flag: String, currentFolder: String) -> DataFolder {
        let url = URL(fileURLWithPath: flag, relativeTo: URL(fileURLWithPath: currentFolder, isDirectory: true))
        return DataFolder(path: url.standardizedFileURL.path)
    }

    private static let usage = """
        Usage: openrun-session [--socket PATH] [--data-folder PATH] [--answerer-requirement REQUIREMENT] [--launch-agent]
                               [--agent-program PROGRAM] [--codex-program PROGRAM] [--own-environment-for-agents]
               openrun-session --build-identifier
               openrun-session --help

        Runs the OpenRun session process in the foreground and logs to standard error.
        The socket is PATH, or OPENRUN_SOCKET, or ~/Library/Application Support/OpenRun/session.socket.
        A relative path starts at the current folder. The folder of the socket must belong to you,
        and other users must not be able to write to it.
        The projects and the settings are in the folder of the socket, or in the folder
        that --data-folder names.
        The agent of a thread is the PROGRAM of --agent-program, or claude, and for a thread
        with Codex the PROGRAM of --codex-program, or codex. It gets the environment of your
        login shell, or with --own-environment-for-agents the environment of this process.
        launchd gives --launch-agent: the process then answers wake requests, and it
        ends after 30 seconds with no session and no client.
        Only a program that meets REQUIREMENT, in the code requirement language, receives
        and answers approval questions. The default is OpenRun.app of the team of this program.
        With --build-identifier alone, the program prints the identifier of its build and ends.
        """

    private static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("openrun-session: \(PrintableText.escaping(message))\n\(usage)\n".utf8))
        return 2
    }
}
