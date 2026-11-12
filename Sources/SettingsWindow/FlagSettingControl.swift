import AppKit

/// A checkbox for a setting that is on or off.
@MainActor final class FlagSettingControl: NSObject, SettingControl {
    let checkbox: NSButton
    var changed: ((String) -> Void)?
    var view: NSView { checkbox }

    init(title: String) {
        checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        super.init()
        (checkbox.target, checkbox.action) = (self, #selector(toggle))
    }

    func show(_ text: String) {
        checkbox.state = text == "on" ? .on : .off
    }

    @objc func toggle() {
        changed?(checkbox.state == .on ? "on" : "off")
    }
}
