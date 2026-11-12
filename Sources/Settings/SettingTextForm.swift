import Foundation

/// The text form of each kind of setting, for `openrun settings get` and
/// `set`. Each value round-trips: the parse of its text gives it back.
enum SettingTextForm {
    static func text(of value: SettingValue) -> String {
        switch value {
        case .text(let text), .choice(let text): return text
        case .wholeNumber(let number): return String(number)
        case .flag(let flag): return flag ? "on" : "off"
        case .commands, .accounts:
            // One line of JSON, so a script can read it back.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = (try? encoder.encode(SettingStoredForm.stored(value))) ?? Data("[]".utf8)
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// The value of the text, or `nil` when it is not a valid value of the
    /// kind. Spaces around a number, a flag or a choice do not count, and
    /// neither does the case of a flag or a choice. Text keeps every
    /// character, so any theme name round-trips.
    static func value(of text: String, as kind: SettingKind) -> SettingValue? {
        let word = text.trimmingCharacters(in: .whitespaces)
        let value: SettingValue? = switch kind {
        case .text: .text(text)
        case .wholeNumber: Int(word).map(SettingValue.wholeNumber)
        case .flag:
            switch word.lowercased() {
            case "on", "true", "yes": .flag(true)
            case "off", "false", "no": .flag(false)
            default: nil
            }
        // The choice keeps its own spelling, such as `acceptEdits`.
        case .choice(let options): options.first { $0.lowercased() == word.lowercased() }.map(SettingValue.choice)
        case .commands, .accounts:
            (try? JSONDecoder().decode(StoredValue.self, from: Data(text.utf8)))
                .flatMap { SettingStoredForm.value(from: $0, as: kind) }
        }
        guard let value, kind.accepts(value) else { return nil }
        return value
    }
}
