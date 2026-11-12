/// How the session process starts the agent of a thread.
struct AgentLaunchSettings: Sendable {
    /// The program of the agent, an absolute path, such as the `claude`
    /// that the login shell of the user finds.
    var program: String
    /// The environment of the login shell of the user (decision of
    /// 2026-11-10). launchd gives the session process a short one.
    var environment: [String: String]
    /// The program and the arguments of the permission hook, which asks
    /// the session process (`openrun permission-request`).
    var hookCommand: String
    var hookArguments: [String]
    /// The program of Codex: a name in the search path of the
    /// environment, or a path. Tests name the fake app-server.
    var codexProgram = "codex"
}
