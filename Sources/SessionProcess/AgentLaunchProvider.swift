import AgentProgram
import Foundation

/// Gives the launch settings of the agents of the threads.
///
/// The environment is the one of the login shell of the user, read once
/// for each start of the session process, at the first need (decision of
/// 2026-11-10). It is never logged. A read can take seconds, so it runs
/// here and not in the registry of the threads.
actor AgentLaunchProvider {
    /// What the command line of the session process can change.
    struct Options: Sendable, Equatable {
        /// The program of Claude Code: a name to find in the `PATH` of
        /// the environment of the agent, or a path. Tests name the fake agent.
        var program = "claude"
        /// Whether the agents get the environment of the session process
        /// in place of the one of the login shell, for tests and for a
        /// session process that a terminal started.
        var usesOwnEnvironment = false
    }

    private let options: Options
    private let socketPath: String
    /// The `openrun` program of this build, which is the permission hook.
    private let toolPath: String
    private var environment: [String: String]?

    init(options: Options, socketPath: String, executablePath: String? = ApplicationBundle.executablePathOfThisProcess()) {
        (self.options, self.socketPath) = (options, socketPath)
        toolPath = Self.toolPath(forSessionProcessAt: executablePath ?? "")
    }

    /// The tool is in the helper folder of the app bundle. In a build
    /// folder of `swift build` it lies beside the session process.
    static func toolPath(forSessionProcessAt path: String) -> String {
        let folder = HelperSearchPath.helperFolder(forExecutableAt: path) ?? (path as NSString).deletingLastPathComponent
        return folder + "/openrun"
    }

    func settings() async -> AgentLaunchSettings {
        if environment == nil { environment = await readEnvironment() }
        return AgentLaunchSettings(program: options.program, environment: environment ?? [:], hookCommand: toolPath, hookArguments: ["permission-request"])
    }

    private func readEnvironment() async -> [String: String] {
        var own = ProcessInfo.processInfo.environment
        if !options.usesOwnEnvironment, let shell = await LoginShellEnvironment.read(base: own, folder: NSHomeDirectory()) {
            own = shell
        }
        // The hook finds the session process of its thread through the socket.
        own["OPENRUN_SOCKET"] = socketPath
        own["OPENRUN_SESSION"] = nil
        return own
    }
}
