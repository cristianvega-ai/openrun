/// The value of one setting, of the kind that its name gives.
enum SettingValue: Hashable, Sendable {
    case text(String)
    case wholeNumber(Int)
    case flag(Bool)
    /// The raw value of `OptionKeyBehavior` or `LinkDestination`.
    case choice(String)
    case commands([NewSessionCommand])
    case accounts([AgentAccount])
}
