import DataStorage

/// The settings that differ from their defaults, by name, and the settings
/// of a later build. A setting at its default stays out of the file, so a
/// later build can change a default that the user never chose.
struct SettingsDocument: DataDocument {
    static let file = DataFile.settings
    static let format = 1
    static let knownKeys: Set<String> = ["settings"]

    var settings: [String: StoredValue]
}
