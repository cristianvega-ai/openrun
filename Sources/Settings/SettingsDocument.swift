import DataStorage

/// The settings that differ from their defaults, each a key at the top of
/// the file beside `format`. A setting at its default stays out of the
/// file, so a later build can change a default that the user never chose.
///
/// A setting of a later build is a key that this build does not know, so
/// `DataFolder` keeps it with the exact text of its value.
struct SettingsDocument: DataDocument {
    static let file = DataFile.settings
    static let format = 1
    static let knownKeys = Set(SettingName.allCases.map(\.rawValue))

    /// The value of each known setting in the file, by name.
    var settings: [String: StoredValue]

    init(settings: [String: StoredValue]) {
        self.settings = settings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SettingKey.self)
        settings = [:]
        for name in SettingName.allCases {
            let key = SettingKey(stringValue: name.rawValue)
            guard container.contains(key) else { continue }
            settings[name.rawValue] = try container.decode(StoredValue.self, forKey: key)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SettingKey.self)
        for (name, value) in settings {
            try container.encode(value, forKey: SettingKey(stringValue: name))
        }
    }
}

/// The name of a setting as a key of the file.
struct SettingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
