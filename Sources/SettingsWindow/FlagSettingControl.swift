import AppKit

/// A switch for a setting that is on or off.
@MainActor final class FlagSettingControl: NSObject, SettingControl {
    let toggle = NSSwitch()
    var changed: ((String) -> Void)?
    var view: NSView { toggle }

    override init() {
        super.init()
        (toggle.target, toggle.action) = (self, #selector(toggled))
    }

    func show(_ text: String) {
        toggle.state = text == "on" ? .on : .off
    }

    @objc func toggled() {
        changed?(toggle.state == .on ? "on" : "off")
    }
}
