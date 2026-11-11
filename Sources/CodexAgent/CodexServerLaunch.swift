import AgentProgram

/// How to start `codex app-server` for one account.
public struct CodexServerLaunch: Sendable, Hashable {
    /// A path, or a bare name to find in the `PATH` of `environment`.
    public var executablePath: String
    /// The `CODEX_HOME` folder of the account, or nil for the default
    /// account of the environment.
    public var accountFolder: String?
    /// The environment of the user's login shell. The app-server gets this
    /// environment and nothing else.
    public var environment: [String: String]
    /// The working folder of the app-server. Each thread has its own.
    public var folder: String

    public init(executablePath: String = "codex", accountFolder: String? = nil, environment: [String: String], folder: String = "/") {
        self.executablePath = executablePath
        self.accountFolder = accountFolder
        self.environment = environment
        self.folder = folder
    }

    /// The launch of the program. The account folder replaces a
    /// `CODEX_HOME` of the environment. Without one, the variable stays as
    /// the login shell set it, because the shell selects the first account.
    var programLaunch: AgentProgramLaunch {
        var environment = environment
        if let accountFolder { environment["CODEX_HOME"] = accountFolder }
        return AgentProgramLaunch(executablePath: executablePath, arguments: ["app-server"], folder: folder, environment: environment)
    }
}
