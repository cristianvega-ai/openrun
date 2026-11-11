import CoreGraphics
import SessionProtocol
import Settings
import TerminalView

/// The settings that the session process sent, as typed values.
enum LiveSettings {
    /// A setting that this build does not know is left out, and a value
    /// that it cannot read stays at its default, so a session process of
    /// a later build does not stop the app.
    static func values(from summaries: [SettingSummary]) -> SettingValues {
        var values = SettingValues()
        for summary in summaries {
            guard let name = SettingName(rawValue: summary.name) else { continue }
            try? values.change(name, to: summary.text, requestedBy: .application)
        }
        return values
    }

    /// Gives a terminal view the settings that concern it. The theme
    /// stays Graphite until the themes arrive.
    @MainActor static func apply(_ values: SettingValues, to view: TerminalView) {
        // The view takes SF Mono for `nil`, and keeps the weights of the
        // system font that the name alone does not give.
        let fontName = values.fontName == "SF Mono" ? nil : values.fontName
        if view.fontName != fontName { view.fontName = fontName }
        if view.standardFontSize != CGFloat(values.fontSize) { view.standardFontSize = CGFloat(values.fontSize) }
        let rule: OptionKeyRule = switch values.optionAsAlt {
        case .left: .left
        case .both: .both
        case .neither: .neither
        }
        if view.optionKeyRule != rule { view.optionKeyRule = rule }
        if view.scrollbackLimit != values.scrollbackLimit { view.scrollbackLimit = values.scrollbackLimit }
    }
}
