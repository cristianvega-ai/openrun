import AppKit
import Settings

/// One pane of the settings window: its title, its symbol and its rows.
struct SettingsPane {
    let title: String
    let symbolName: String
    let rows: [SettingRow]

    /// - Parameter permissionModeTitle: The words of the app for a
    ///   permission mode of Claude Code, as the chat shows them.
    @MainActor static func all(permissionModeTitle: @escaping (String) -> String) -> [SettingsPane] {
        [general, appearance, terminal, agents(permissionModeTitle: permissionModeTitle)]
    }

    @MainActor private static var general: SettingsPane {
        SettingsPane(title: "General", symbolName: "gearshape", rows: [
            SettingRow(name: SettingName.linkDestination.rawValue, label: "Open links in") {
                ChoiceSettingControl([("default-browser", "The Default Browser"), ("browser-split", "A Web Page Beside the Session")])
            },
            SettingRow(name: SettingName.showsNotifications.rawValue, label: "Notifications") {
                FlagSettingControl(title: "Show a notification when a session needs you")
            },
            SettingRow(name: SettingName.sessionLimit.rawValue, label: "Sessions", note: "The most sessions that run at one time.") {
                NumberSettingControl(1...1_000)
            },
        ])
    }

    @MainActor private static var appearance: SettingsPane {
        SettingsPane(title: "Appearance", symbolName: "paintbrush", rows: [
            SettingRow(name: SettingName.theme.rawValue, label: "Theme") { ChoiceSettingControl([("graphite", "Graphite")]) },
            SettingRow(name: SettingName.fontName.rawValue, label: "Font") { ChoiceSettingControl(fixedPitchFonts.map { ($0, $0) }) },
            SettingRow(name: SettingName.fontSize.rawValue, label: "Size") { NumberSettingControl(6...72, unit: "points") },
        ])
    }

    @MainActor private static var terminal: SettingsPane {
        SettingsPane(title: "Terminal", symbolName: "terminal", rows: [
            SettingRow(name: SettingName.optionAsAlt.rawValue, label: "Option key", note: "An Option key that is not Alt types the special characters of the keyboard.") {
                ChoiceSettingControl([("left", "The Left Option Key Is Alt"), ("both", "Both Option Keys Are Alt"), ("neither", "No Option Key Is Alt")])
            },
            SettingRow(name: SettingName.scrollbackLimit.rawValue, label: "Scrollback") { NumberSettingControl(0...1_000_000, unit: "lines") },
            SettingRow(name: SettingName.asksBeforeUnsafePaste.rawValue, label: "Paste") {
                FlagSettingControl(title: "Ask before a paste that could run a command")
            },
            SettingRow(name: SettingName.newSessionCommands.rawValue, label: "New sessions", note: "The commands of the new-session button. An empty command starts the login shell.") {
                EntryListSettingControl()
            },
        ])
    }

    @MainActor private static func agents(permissionModeTitle: @escaping (String) -> String) -> SettingsPane {
        SettingsPane(title: "Agents", symbolName: "sparkles", rows: [
            SettingRow(name: SettingName.claudeCodeModel.rawValue, label: "Model", note: "The model of a new thread with Claude Code.") {
                TextSettingControl(suggestions: ["fable", "opus", "sonnet", "haiku"])
            },
            SettingRow(
                name: SettingName.claudeCodePermissionMode.rawValue, label: "Permission mode",
                note: "A new thread starts in this mode. In its chat, a thread can take this mode and each stricter one."
            ) {
                ChoiceSettingControl(SettingName.claudeCodePermissionModes.map { ($0, permissionModeTitle($0)) })
            },
            SettingRow(name: SettingName.claudeCodeProgram.rawValue, label: "Claude Code", note: "The name of the program in your shell, or its full path.") {
                TextSettingControl(placeholder: "claude")
            },
            SettingRow(name: SettingName.agentProcessLimit.rawValue, label: "Agents", note: "The most agents that work at one time. Each one uses about 400 MB of memory.") {
                NumberSettingControl(1...32)
            },
            SettingRow(
                name: SettingName.claudeCodeAccounts.rawValue, label: "Claude Code accounts",
                note: "The other logins of Claude Code, each with the folder of its settings. The login of your shell needs no entry."
            ) { accountList() },
            SettingRow(name: SettingName.codexAccounts.rawValue, label: "Codex accounts", note: "The other logins of Codex, each with its Codex home folder.") {
                accountList()
            },
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
