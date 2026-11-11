import UntrustedText

/// A setting could not be read or changed. Nothing changed.
///
/// The messages never show a value that a client sent, and show an unknown
/// name only with its control characters escaped, because the tool prints
/// them in a terminal.
public enum SettingError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownName(String)
    /// The text is not a valid value of the setting.
    case invalidValue(SettingName)
    /// Only OpenRun.app can change this setting.
    case protectedSetting(SettingName)

    public var description: String {
        switch self {
        case .unknownName(let name):
            "OpenRun has no setting \(QuotedText.quoted(name, characterLimit: 64)). Run `openrun settings list` to see the settings."
        case .invalidValue(let setting):
            "The setting \(setting.rawValue) takes \(setting.kind.requirement)."
        case .protectedSetting(let setting):
            "The setting \(setting.rawValue) is protected. Change it in the settings window of OpenRun."
        }
    }
}
