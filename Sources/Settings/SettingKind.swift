import Foundation

/// The kind of value of a setting: what it accepts, its text form for the
/// tool, and its form in `settings.json`.
enum SettingKind: Sendable {
    case text(lengthLimit: Int)
    case wholeNumber(ClosedRange<Int>)
    /// On or off.
    case flag
    /// One of these raw values.
    case choice([String])
    case commands

    /// What a valid value is, for the message of an error.
    var requirement: String {
        switch self {
        case .text(let limit):
            "text of 1 to \(limit) characters with no control characters"
        case .wholeNumber(let range):
            "a whole number from \(range.lowerBound) to \(range.upperBound)"
        case .flag:
            "on or off"
        case .choice(let options):
            "one of " + options.joined(separator: ", ")
        case .commands:
            "a JSON list of at most \(NewSessionCommand.countLimit) objects, each with a \"name\" of 1 to "
                + "\(NewSessionCommand.nameLengthLimit) characters and a \"command\" of at most "
                + "\(NewSessionCommand.commandLineLengthLimit), with no control characters"
        }
    }

    /// Whether a value is of this kind and in its range.
    func accepts(_ value: SettingValue) -> Bool {
        switch (self, value) {
        case (.text(let limit), .text(let text)): SettingText.isPlain(text, lengthLimit: limit)
        case (.wholeNumber(let range), .wholeNumber(let number)): range.contains(number)
        case (.flag, .flag): true
        case (.choice(let options), .choice(let choice)): options.contains(choice)
        case (.commands, .commands(let commands)):
            commands.count <= NewSessionCommand.countLimit && commands.allSatisfy(\.isValid)
        default: false
        }
    }
}
