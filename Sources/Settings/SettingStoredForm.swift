/// The form of each kind of setting in `settings.json`: a JSON string,
/// whole number or boolean, and a list of objects for the commands.
enum SettingStoredForm {
    static func stored(_ value: SettingValue) -> StoredValue {
        switch value {
        case .text(let text), .choice(let text): .string(text)
        case .wholeNumber(let number): .integer(Int64(number))
        case .flag(let flag): .flag(flag)
        case .commands(let commands):
            .array(commands.map { .object(["name": .string($0.name), "command": .string($0.commandLine)]) })
        }
    }

    /// The value, or `nil` when the stored value is of another type or out
    /// of the range of the kind.
    static func value(from stored: StoredValue, as kind: SettingKind) -> SettingValue? {
        let value: SettingValue? = switch (kind, stored) {
        case (.text, .string(let text)): .text(text)
        case (.choice, .string(let text)): .choice(text)
        case (.wholeNumber, .integer(let number)): Int(exactly: number).map(SettingValue.wholeNumber)
        case (.wholeNumber, .number(let number)): Int(exactly: number).map(SettingValue.wholeNumber)
        case (.flag, .flag(let flag)): .flag(flag)
        case (.commands, .array(let entries)): commands(from: entries).map(SettingValue.commands)
        default: nil
        }
        guard let value, kind.accepts(value) else { return nil }
        return value
    }

    private static func commands(from entries: [StoredValue]) -> [NewSessionCommand]? {
        var commands: [NewSessionCommand] = []
        for entry in entries {
            guard case .object(let fields) = entry, fields.count == 2,
                  case .string(let name) = fields["name"],
                  case .string(let commandLine) = fields["command"] else { return nil }
            commands.append(NewSessionCommand(name: name, commandLine: commandLine))
        }
        return commands
    }
}
