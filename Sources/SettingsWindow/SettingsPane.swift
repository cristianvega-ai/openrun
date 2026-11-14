import AppKit
import Settings

/// One pane of the settings window: its title, its symbol, and its
/// settings in sections.
struct SettingsPane {
    let title: String
    let symbolName: String
    let sections: [SettingsSection]

    var rows: [SettingRow] { sections.flatMap(\.rows) }

    init(title: String, symbolName: String, sections: [SettingsSection]) {
        (self.title, self.symbolName, self.sections) = (title, symbolName, sections)
    }

    /// A pane with one group that has no heading.
    init(title: String, symbolName: String, rows: [SettingRow]) {
        self.init(title: title, symbolName: symbolName, sections: [SettingsSection(rows: rows)])
    }

    /// The panes in the groups of the list at the left of the window:
    /// the app, the agents, and the limits.
    ///
    /// - Parameter permissionModeTitle: The words of the app for a
    ///   permission mode of Claude Code, as the chat shows them.
    @MainActor static func groups(permissionModeTitle: @escaping (String) -> String) -> [[SettingsPane]] {
        [[general, appearance, terminal], [accounts, claudeCode(permissionModeTitle: permissionModeTitle)], [limits]]
    }

    @MainActor private static var general: SettingsPane {
        SettingsPane(title: "General", symbolName: "gearshape", rows: [
            SettingRow(name: SettingName.showsNotifications.rawValue, label: "Notifications", note: "macOS tells you when a thread or a terminal needs you.") {
                FlagSettingControl()
            },
            SettingRow(name: SettingName.linkDestination.rawValue, label: "Open links", note: "A web link that you Command-click in a terminal, or click in a chat.") {
                ChoiceSettingControl([("default-browser", "In the Default Browser"), ("browser-split", "In a Web Page Beside the Work")])
            },
        ])
    }

    @MainActor private static var appearance: SettingsPane {
        SettingsPane(title: "Appearance", symbolName: "paintbrush", sections: [
            SettingsSection(rows: [
                SettingRow(name: SettingName.theme.rawValue, label: "Theme", note: "The colors of the whole window. They follow the light or the dark appearance of macOS.") {
                    ChoiceSettingControl([("graphite", "Graphite")])
                },
            ]),
            SettingsSection(title: "Terminal Text", rows: [
                SettingRow(name: SettingName.fontName.rawValue, label: "Font", note: "Each font of the list has one width for every character.") {
                    ChoiceSettingControl(fixedPitchFonts.map { ($0, $0) })
                },
                SettingRow(name: SettingName.fontSize.rawValue, label: "Size") { NumberSettingControl(6...72, unit: "points") },
            ]),
        ])
    }

    @MainActor private static var terminal: SettingsPane {
        SettingsPane(title: "Terminal", symbolName: "terminal", sections: [
            SettingsSection(rows: [
                SettingRow(name: SettingName.optionAsAlt.rawValue, label: "Option key as Alt", note: "The Option keys that are Alt. An Option key that is not Alt types the special characters of the keyboard.") {
                    SegmentSettingControl([("left", "Left"), ("both", "Both"), ("neither", "Neither")])
                },
                SettingRow(name: SettingName.scrollbackLimit.rawValue, label: "Scrollback", note: "The lines that each terminal keeps above its screen.") {
                    NumberSettingControl(0...1_000_000, unit: "lines")
                },
                SettingRow(name: SettingName.asksBeforeUnsafePaste.rawValue, label: "Ask before an unsafe paste", note: "OpenRun asks before a paste that could run a command.") {
                    FlagSettingControl()
                },
            ]),
            SettingsSection(title: "New Terminals", note: "The New Thread or Terminal button offers a terminal with each command.", rows: [
                SettingRow(name: SettingName.newSessionCommands.rawValue, label: "Commands") { EntryListSettingControl() },
            ]),
        ])
    }

    /// The logins of each agent. The New Thread or Terminal button
    /// offers a thread under each one.
    static let accountsTitle = "Accounts"

    @MainActor private static var accounts: SettingsPane {
        SettingsPane(title: accountsTitle, symbolName: "person.crop.circle", sections: [
            SettingsSection(title: "Claude Code", note: "Each account is one login of Claude Code. A new thread runs under the account that you choose for it.", rows: [
                SettingRow(name: SettingName.claudeCodeAccounts.rawValue, label: "Accounts") { accountList(program: "claude") },
            ]),
            SettingsSection(title: "Codex", note: "Each account is one login of Codex, with its Codex home folder.", rows: [
                SettingRow(name: SettingName.codexAccounts.rawValue, label: "Accounts") { accountList(program: "codex") },
            ]),
        ])
    }

    @MainActor private static func claudeCode(permissionModeTitle: @escaping (String) -> String) -> SettingsPane {
        SettingsPane(title: "Claude Code", symbolName: "sparkles", rows: [
            SettingRow(name: SettingName.claudeCodeModel.rawValue, label: "Model", note: "A new thread starts with this model. You can change it in each chat.") {
                TextSettingControl(suggestions: ["fable", "opus", "sonnet", "haiku"])
            },
            SettingRow(
                name: SettingName.claudeCodePermissionMode.rawValue, label: "Permission mode",
                note: "A new thread starts in this mode. In its chat, a thread can take this mode and each stricter one."
            ) {
                ChoiceSettingControl(SettingName.claudeCodePermissionModes.map { ($0, permissionModeTitle($0)) })
            },
            SettingRow(name: SettingName.claudeCodeProgram.rawValue, label: "Program", note: "The name of the Claude Code program in your shell, or its full path.") {
                TextSettingControl(placeholder: "claude")
            },
        ])
    }

    @MainActor private static var limits: SettingsPane {
        SettingsPane(title: "Limits", symbolName: "speedometer", rows: [
            SettingRow(name: SettingName.sessionLimit.rawValue, label: "Terminals", note: "The most terminals that run at one time.") { NumberSettingControl(1...1_000) },
            SettingRow(name: SettingName.agentProcessLimit.rawValue, label: "Agents", note: "The most agents that work at one time. Each one uses about 400 MB of memory.") {
                NumberSettingControl(1...32)
            },
        ])
    }

    /// The list of the accounts of an agent. The button that adds an
    /// account asks for the folder of its settings.
    @MainActor private static func accountList(program: String) -> EntryListSettingControl {
        let control = EntryListSettingControl(.account(program: program))
        control.chooseDetail = EntryListSettingControl.chooseFolder
        return control
    }

    /// The font families of this Mac in which every character has the
    /// same width, after the font of the system.
    @MainActor static var fixedPitchFonts: [String] {
        let manager = NSFontManager.shared
        return ["SF Mono"] + manager.availableFontFamilies.filter { family in
            family != "SF Mono" && manager.font(withFamily: family, traits: [], weight: 5, size: 12)?.isFixedPitch == true
        }
    }
}
