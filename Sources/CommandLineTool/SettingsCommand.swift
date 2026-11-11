import SessionConnection
import SessionProtocol
import Settings
import UntrustedText

/// `openrun settings list`, `get` and `set`.
struct SettingsCommand {
    enum Action: Equatable {
        case list
        case get(name: String)
        case set(name: String, text: String)
    }

    var action: Action

    func run(location: SocketLocation) throws -> String {
        let client = try SessionClient(location: location)
        switch action {
        case .list:
            return Self.lines(of: try client.settings())
        case .get(let name):
            guard let setting = try client.settings().first(where: { $0.name == name }) else {
                throw CommandLineToolError.failure(SettingError.unknownName(name).description)
            }
            return Self.printable(setting.text) + "\n"
        case .set(let name, let text):
            try client.changeSetting(named: name, to: text)
            return ""
        }
    }

    /// One line for each setting: the name, a tab, and the text. A protected
    /// setting has a third column, `protected`, so a script that reads the
    /// first two columns can ignore the mark.
    static func lines(of settings: [SettingSummary]) -> String {
        settings
            .map { setting in
                ([setting.name, setting.text].map(printable) + (setting.isProtected ? ["protected"] : [])).joined(separator: "\t") + "\n"
            }
            .joined()
    }

    /// The text that `settings set` takes back: a backslash stays one
    /// backslash, so the JSON of the commands round-trips. The control
    /// characters are escaped, so a value cannot add a column or a line, or
    /// control the terminal. No valid value holds one.
    static func printable(_ text: String) -> String {
        PrintableText.escapingControlCharacters(in: text)
    }
}
