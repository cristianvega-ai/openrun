import AppKit
import ListContent
import SettingsWindow

/// The settings window and its way to the session process.
extension Workspace {
    /// The text of each setting by its name, as the feed gave them.
    var settingTexts: [String: String] {
        Dictionary(connection.overview.settings.map { ($0.name, $0.text) }, uniquingKeysWith: { first, _ in first })
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let controller = SettingsWindowController(permissionModeTitle: ThreadRowFacts.permissionModeTitle)
            controller.change = { [weak self] name, text in self?.changeSetting(name, to: text) }
            settingsWindow = controller
        }
        settingsWindow?.show(settingTexts)
        // The Accounts pane shows the same usage as the foot of the first pane.
        settingsWindow?.showUsage(window.projectsList.content.accounts)
        settingsWindow?.showWindow(sender)
    }

    /// Sends a change of the settings window. The feed brings the new
    /// value to the window and to the panes. After a refusal, the window
    /// shows the values of the session process again.
    func changeSetting(_ name: String, to text: String) {
        requests.perform({ try $0.changeSetting(named: name, to: text) }, then: { [weak self] result in
            guard let self, case .failure(let failure) = result else { return }
            settingsWindow?.show(settingTexts)
            showSettingFailure(failure.message)
        })
    }

    /// Tells why a setting did not change, in a sheet on the settings window.
    func showSettingFailureSheet(_ message: String) {
        guard let window = settingsWindow?.window, window.isVisible else { return showFailure("The setting did not change", message) }
        let alert = NSAlert()
        (alert.messageText, alert.informativeText) = ("The setting did not change", message)
        alert.beginSheetModal(for: window)
    }
}
