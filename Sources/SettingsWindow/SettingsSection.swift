/// The settings of one pane that belong together, under a title, so a
/// user sees what each group is for.
struct SettingsSection {
    /// The words over the group, or `nil` for a group with no heading.
    var title: String?
    /// A line under the title that tells what the group does.
    var note: String?
    let rows: [SettingRow]
}
