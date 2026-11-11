import DataStorage

/// Loads and saves the settings in `settings.json` in the data folder.
public struct SettingsStore: Sendable {
    public let dataFolder: DataFolder

    public init(dataFolder: DataFolder = .default) {
        self.dataFolder = dataFolder
    }

    /// Reads the file. A file that cannot be read is set aside, and every
    /// setting starts at its default. A setting whose value is of the wrong
    /// type or out of range starts at its default, and the others keep
    /// their values.
    ///
    /// - Throws: `DataStorageError` when the file exists but the system
    ///   cannot read or move it. A save then throws too, so it never
    ///   replaces settings that the load did not read.
    public func load() throws -> LoadedSettings {
        let result = try dataFolder.read(SettingsDocument.self)
        var setAsidePath: String?
        if case .setAside(let path) = result { setAsidePath = path }
        let (values, fallbackNames) = Self.values(from: result.document?.settings ?? [:])
        return LoadedSettings(values: values, fallbackNames: fallbackNames, setAsidePath: setAsidePath)
    }

    /// Makes the data folder when it does not exist, and writes the file.
    public func save(_ values: SettingValues) throws {
        try dataFolder.create()
        try dataFolder.write(SettingsDocument(settings: Self.stored(values)))
    }

    static func values(from stored: [String: StoredValue]) -> (SettingValues, [SettingName]) {
        var values = SettingValues()
        var fallbackNames: [SettingName] = []
        for (key, storedValue) in stored {
            guard let name = SettingName(rawValue: key) else {
                values.unknownSettings[key] = storedValue
                continue
            }
            guard let value = SettingStoredForm.value(from: storedValue, as: name.kind) else {
                fallbackNames.append(name)
                continue
            }
            values.set(name, checked: value)
        }
        return (values, fallbackNames.sorted { $0.rawValue < $1.rawValue })
    }

    static func stored(_ values: SettingValues) -> [String: StoredValue] {
        var stored = values.unknownSettings
        for (name, value) in values.values where value != name.defaultValue {
            stored[name.rawValue] = SettingStoredForm.stored(value)
        }
        return stored
    }
}
