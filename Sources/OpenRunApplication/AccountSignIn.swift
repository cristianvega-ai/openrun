/// The command line of Sign In in the Accounts pane (decision of
/// 2026-11-13): the agent's own login, in a terminal, under the folder of
/// the settings of the account. The login happens between the user and
/// the agent, so OpenRun never reads, keeps or sends a credential.
struct AccountSignIn: Equatable {
    /// The agent as the session process names it, such as `claude-code`.
    let agent: String
    /// The name of the program of the agent in the shell, or its full path.
    let program: String
    /// The folder of the settings of the account, or `nil` for the login
    /// of the shell, whose own environment chooses the folder.
    let folder: String?

    /// The login command of the agent: `claude auth login`, or `codex login`.
    /// The folder goes in through `env`, after the files of the login
    /// shell, so a variable that those files set cannot take its place.
    var commandLine: String? {
        let (variable, arguments) = switch agent {
        case "claude-code": ("CLAUDE_CONFIG_DIR", "auth login")
        case "codex": ("CODEX_HOME", "login")
        default: ("", "")
        }
        guard !variable.isEmpty else { return nil }
        let account = folder.map { "env \(variable)=\(Self.quoted($0)) " } ?? ""
        return account + Self.quoted(program) + " " + arguments
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
