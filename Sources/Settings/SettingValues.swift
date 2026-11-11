/// The value of every setting, and the settings of a later build that this
/// build keeps as they are.
public struct SettingValues: Hashable, Sendable {
    /// Holds every name. Each value is of the kind of its name and in its
    /// range, because each way in checks it.
    private(set) var values: [SettingName: SettingValue]
    /// The settings in the file that this build does not know, by their
    /// names. A save writes them back unchanged.
    var unknownSettings: [String: StoredValue] = [:]

    /// Every setting at its default.
    public init() {
        values = Dictionary(uniqueKeysWithValues: SettingName.allCases.map { ($0, $0.defaultValue) })
    }

    public var theme: String { text(of: .theme) }
    public var fontName: String { text(of: .fontName) }
    public var fontSize: Int { wholeNumber(.fontSize) }
    public var optionAsAlt: OptionKeyBehavior { OptionKeyBehavior(rawValue: text(of: .optionAsAlt)) ?? .left }
    public var scrollbackLimit: Int { wholeNumber(.scrollbackLimit) }
    public var newSessionCommands: [NewSessionCommand] {
        guard case .commands(let commands) = values[.newSessionCommands] else { return NewSessionCommand.defaults }
        return commands
    }
    public var linkDestination: LinkDestination { LinkDestination(rawValue: text(of: .linkDestination)) ?? .defaultBrowser }
    public var showsNotifications: Bool { flag(.showsNotifications) }
    public var sessionLimit: Int { wholeNumber(.sessionLimit) }
    public var asksBeforeUnsafePaste: Bool { flag(.asksBeforeUnsafePaste) }

    /// The text form of a setting, as `openrun settings get` prints it.
    public func text(of name: SettingName) -> String {
        SettingTextForm.text(of: values[name] ?? name.defaultValue)
    }

    /// The one way to change a setting, for the settings window and for
    /// `openrun settings set` alike.
    ///
    /// - Throws: `SettingError.protectedSetting` when a client other than
    ///   the app asks for a protected setting, whatever the text, or
    ///   `SettingError.invalidValue` when the text is not a valid value.
    public mutating func change(_ name: SettingName, to text: String, requestedBy requester: SettingRequester) throws {
        if name.isProtected, requester != .application {
            throw SettingError.protectedSetting(name)
        }
        guard let value = SettingTextForm.value(of: text, as: name.kind) else {
            throw SettingError.invalidValue(name)
        }
        values[name] = value
    }

    /// Puts a value that was checked against the kind of its name.
    mutating func set(_ name: SettingName, checked value: SettingValue) {
        values[name] = value
    }

    private func wholeNumber(_ name: SettingName) -> Int {
        if case .wholeNumber(let number) = values[name] { return number }
        if case .wholeNumber(let number) = name.defaultValue { return number }
        return 0
    }

    private func flag(_ name: SettingName) -> Bool {
        if case .flag(let flag) = values[name] { return flag }
        return name.defaultValue == .flag(true)
    }
}
