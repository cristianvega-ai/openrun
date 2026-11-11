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

    /// A protected setting removes a question or widens what an agent can
    /// do, so only OpenRun.app can change it (decision of 2026-10-27). Any
    /// client can read it.
    public var isProtected: Bool {
        self == .sessionLimit || self == .asksBeforeUnsafePaste
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
        case .theme, .fontName: .text(lengthLimit: 100)
        case .fontSize: .wholeNumber(6...72)
        case .optionAsAlt: .choice(OptionKeyBehavior.allCases.map(\.rawValue))
        case .scrollbackLimit: .wholeNumber(0...1_000_000)
        case .newSessionCommands: .commands
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
        }
    }
}
