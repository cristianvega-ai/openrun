import AppKit

/// The control of one setting in the settings window. It shows the text
/// of the setting as the session process gives it, and it tells the new
/// text when the user changes the value. It changes nothing itself.
@MainActor protocol SettingControl: AnyObject {
    var view: NSView { get }
    var changed: ((String) -> Void)? { get set }
    func show(_ text: String)
    /// A wide control, such as a list, fills its card. Each other
    /// control stands at the right of the name of its setting.
    var isWide: Bool { get }
}

extension SettingControl {
    var isWide: Bool { false }
}
