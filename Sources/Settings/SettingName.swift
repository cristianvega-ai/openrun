/// A setting of version 1, by its name for `openrun settings`.
///
/// The names are lower-case full words joined by hyphens. They also are the
/// keys of `settings.json`, so a name never changes once it ships.
public enum SettingName: String, CaseIterable, Hashable, Sendable {
    /// The name of the color theme. Any name round-trips, so a later
    /// theme needs no change here.
    case theme = "theme"
    case fontName = "font-name"
    /// In points.
    case fontSize = "font-size"
    /// Which Option keys type as Alt.
    case optionAsAlt = "option-as-alt"
    /// The most lines that each session keeps above its screen.
    case scrollbackLimit = "scrollback-limit"
    /// The commands of the new-session button, in their order.
    case newSessionCommands = "new-session-commands"
    /// Where a link that the user opens goes.
    case linkDestination = "open-links-in"
    case showsNotifications = "notifications"
    /// The most sessions that run at once. Protected.
    case sessionLimit = "session-limit"
    /// Whether a paste that could run a command asks first. Protected.
    case asksBeforeUnsafePaste = "ask-before-unsafe-paste"
    /// The model of a new thread with Claude Code: a name that
    /// `claude --model` takes, such as `opus`.
    case claudeCodeModel = "claude-code-model"
    /// The permission mode of a new thread with Claude Code, and the
    /// widest mode that a thread can take (proposal 9). Protected.
    case claudeCodePermissionMode = "claude-code-permission-mode"
    /// The program of Claude Code: a name that the login shell of the
    /// user finds, or a path. Protected, because another program could
    /// leave out the permission hook.
    case claudeCodeProgram = "claude-code-program"
    /// The most agent processes that run at one time. Protected.
    case agentProcessLimit = "agent-process-limit"
    /// The other accounts of Claude Code, after the one of the login
    /// shell. Protected, because the folder of an account holds the
    /// settings of the agent, and they can widen what it may do.
    case claudeCodeAccounts = "claude-code-accounts"
    /// The other accounts of Codex. Protected for the same reason.
    case codexAccounts = "codex-accounts"

    /// The permission modes of Claude Code that OpenRun uses, from the
    /// strictest to the widest.
    public static let claudeCodePermissionModes = ["plan", "dontAsk", "default", "acceptEdits", "auto"]

    /// A protected setting removes a question or widens what an agent can
    /// do, so only OpenRun.app can change it (decision of 2026-10-27). Any
    /// client can read it.
    public var isProtected: Bool {
        switch self {
        case .sessionLimit, .asksBeforeUnsafePaste, .claudeCodePermissionMode, .claudeCodeProgram, .agentProcessLimit: true
        case .claudeCodeAccounts, .codexAccounts: true
        default: false
        }
    }

    /// The setting with this name.
    ///
    /// - Throws: `SettingError.unknownName`.
    public static func named(_ name: String) throws -> SettingName {
        guard let setting = SettingName(rawValue: name) else { throw SettingError.unknownName(name) }
        return setting
    }

    var kind: SettingKind {
        switch self {
        case .theme, .fontName, .claudeCodeModel: .text(lengthLimit: 100)
        case .claudeCodeProgram: .text(lengthLimit: 1_000)
        case .claudeCodePermissionMode: .choice(Self.claudeCodePermissionModes)
        case .agentProcessLimit: .wholeNumber(1...32)
        case .fontSize: .wholeNumber(6...72)
        case .optionAsAlt: .choice(OptionKeyBehavior.allCases.map(\.rawValue))
        case .scrollbackLimit: .wholeNumber(0...1_000_000)
        case .newSessionCommands: .commands
        case .claudeCodeAccounts, .codexAccounts: .accounts
        case .linkDestination: .choice(LinkDestination.allCases.map(\.rawValue))
        case .showsNotifications, .asksBeforeUnsafePaste: .flag
        case .sessionLimit: .wholeNumber(1...1000)
        }
    }

    var defaultValue: SettingValue {
        switch self {
        case .theme: .text("graphite")
        case .fontName: .text("SF Mono")
        case .fontSize: .wholeNumber(13)
        case .optionAsAlt: .choice(OptionKeyBehavior.left.rawValue)
        case .scrollbackLimit: .wholeNumber(10_000)
        case .newSessionCommands: .commands(NewSessionCommand.defaults)
        case .linkDestination: .choice(LinkDestination.defaultBrowser.rawValue)
        case .showsNotifications, .asksBeforeUnsafePaste: .flag(true)
        case .sessionLimit: .wholeNumber(100)
        case .claudeCodeModel: .text("opus")
        case .claudeCodePermissionMode: .choice("default")
        case .claudeCodeProgram: .text("claude")
        case .agentProcessLimit: .wholeNumber(8)
        case .claudeCodeAccounts, .codexAccounts: .accounts([])
        }
    }
}
