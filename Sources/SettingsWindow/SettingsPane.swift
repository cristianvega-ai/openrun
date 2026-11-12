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

    /// - Parameter permissionModeTitle: The words of the app for a
    ///   permission mode of Claude Code, as the chat shows them.
    @MainActor static func all(permissionModeTitle: @escaping (String) -> String) -> [SettingsPane] {
        [general, appearance, terminal, claudeCode(permissionModeTitle: permissionModeTitle), codex, advanced]
    }

    @MainActor private static var general: SettingsPane {
        SettingsPane(title: "General", symbolName: "gearshape", sections: [
            SettingsSection(title: "Notifications", rows: [
                SettingRow(name: SettingName.showsNotifications.rawValue, label: "") {
                    FlagSettingControl(title: "Notify me when a thread or a terminal needs me")
                },
            ]),
            SettingsSection(title: "Links", note: "A web link that you Command-click in a terminal, or click in a chat.", rows: [
                SettingRow(name: SettingName.linkDestination.rawValue, label: "Open links") {
                    ChoiceSettingControl([("default-browser", "In the Default Browser"), ("browser-split", "In a Web Page Beside the Work")])
                },
            ]),
        ])
    }

    @MainActor private static var appearance: SettingsPane {
        SettingsPane(title: "Appearance", symbolName: "paintbrush", sections: [
            SettingsSection(title: "Colors", rows: [
                SettingRow(name: SettingName.theme.rawValue, label: "Theme") { ChoiceSettingControl([("graphite", "Graphite")]) },
            ]),
            SettingsSection(title: "Terminal Text", rows: [
                SettingRow(name: SettingName.fontName.rawValue, label: "Font") { ChoiceSettingControl(fixedPitchFonts.map { ($0, $0) }) },
                SettingRow(name: SettingName.fontSize.rawValue, label: "Size") { NumberSettingControl(6...72, unit: "points") },
            ]),
        ])
    }

    @MainActor private static var terminal: SettingsPane {
        SettingsPane(title: "Terminal", symbolName: "terminal", sections: [
            SettingsSection(title: "Keyboard", rows: [
                SettingRow(name: SettingName.optionAsAlt.rawValue, label: "Option key", note: "An Option key that is not Alt types the special characters of the keyboard.") {
                    ChoiceSettingControl([("left", "The Left Option Key Is Alt"), ("both", "Both Option Keys Are Alt"), ("neither", "No Option Key Is Alt")])
                },
            ]),
            SettingsSection(title: "Scrollback", note: "The lines that each terminal keeps above its screen.", rows: [
                SettingRow(name: SettingName.scrollbackLimit.rawValue, label: "Keep") { NumberSettingControl(0...1_000_000, unit: "lines") },
            ]),
            SettingsSection(title: "Paste", rows: [
                SettingRow(name: SettingName.asksBeforeUnsafePaste.rawValue, label: "") {
                    FlagSettingControl(title: "Ask before a paste that could run a command")
                },
            ]),
            SettingsSection(
                title: "New Terminals", note: "The New Thread or Terminal button offers a terminal with each command. An empty command starts your login shell.",
                rows: [SettingRow(name: SettingName.newSessionCommands.rawValue, label: "Commands") { EntryListSettingControl() }]),
        ])
    }

    @MainActor private static func claudeCode(permissionModeTitle: @escaping (String) -> String) -> SettingsPane {
        SettingsPane(title: "Claude Code", symbolName: "sparkles", sections: [
            SettingsSection(title: "New Threads", rows: [
                SettingRow(name: SettingName.claudeCodeModel.rawValue, label: "Model", note: "A new thread starts with this model. You can change it in each chat.") {
                    TextSettingControl(suggestions: ["fable", "opus", "sonnet", "haiku"])
                },
                SettingRow(
                    name: SettingName.claudeCodePermissionMode.rawValue, label: "Permission mode",
                    note: "A new thread starts in this mode. In its chat, a thread can take this mode and each stricter one."
                ) {
                    ChoiceSettingControl(SettingName.claudeCodePermissionModes.map { ($0, permissionModeTitle($0)) })
                },
            ]),
            SettingsSection(
                title: "Accounts",
                note: "Each account is one login of Claude Code, with the folder of its settings. The New Thread or Terminal button offers a thread under each account. The login of your shell needs no entry.",
                rows: [SettingRow(name: SettingName.claudeCodeAccounts.rawValue, label: "Logins") { accountList() }]),
        ])
    }

    @MainActor private static var codex: SettingsPane {
        SettingsPane(title: "Codex", symbolName: "curlybraces", sections: [
            SettingsSection(
                title: "Accounts",
                note: "Each account is one login of Codex, with its Codex home folder. The login of your shell needs no entry. A thread with Codex takes its model and its sandbox in its chat.",
                rows: [SettingRow(name: SettingName.codexAccounts.rawValue, label: "Logins") { accountList() }]),
        ])
    }

    @MainActor private static var advanced: SettingsPane {
        SettingsPane(title: "Advanced", symbolName: "gearshape.2", sections: [
            SettingsSection(title: "Limits", note: "The most that run at one time. A request for one more waits or gets a refusal.", rows: [
                SettingRow(name: SettingName.sessionLimit.rawValue, label: "Terminals") { NumberSettingControl(1...1_000) },
                SettingRow(name: SettingName.agentProcessLimit.rawValue, label: "Agents", note: "Each agent that works uses about 400 MB of memory.") {
                    NumberSettingControl(1...32)
                },
            ]),
            SettingsSection(title: "Programs", rows: [
                SettingRow(name: SettingName.claudeCodeProgram.rawValue, label: "Claude Code", note: "The name of the program in your shell, or its full path.") {
                    TextSettingControl(placeholder: "claude")
                },
            ]),
        ])
    }

    /// The list of the accounts of an agent. The plus button asks for
    /// the folder of the new account.
    @MainActor private static func accountList() -> EntryListSettingControl {
        let control = EntryListSettingControl(.settingsFolder)
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
