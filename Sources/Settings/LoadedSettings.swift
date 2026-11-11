/// What `SettingsStore.load` found.
public struct LoadedSettings: Sendable {
    public let values: SettingValues
    /// The settings whose stored value was of the wrong type or out of
    /// range, and that are at their defaults now.
    public let fallbackNames: [SettingName]
    /// The new path of the file when it could not be read and was set
    /// aside. The caller must not log the path in public.
    public let setAsidePath: String?
}
