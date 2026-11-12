/// One setting in a pane of the settings window.
struct SettingRow {
    /// The name of the setting, as `openrun settings` knows it.
    let name: String
    /// The words before the control. Empty for a checkbox, which has its own.
    let label: String
    /// A line of quiet text under the control.
    var note: String?
    let makeControl: @MainActor () -> any SettingControl
}
