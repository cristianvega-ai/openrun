import AppKit

/// The control of one setting in the settings window. It shows the text
/// of the setting as the session process gives it, and it tells the new
/// text when the user changes the value. It changes nothing itself.
@MainActor protocol SettingControl: AnyObject {
    var view: NSView { get }
    var changed: ((String) -> Void)? { get set }
    func show(_ text: String)
}
