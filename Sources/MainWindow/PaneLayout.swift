import Foundation

/// The widths of the first two panes and whether each one is hidden. The app
/// keeps it in its defaults, so the window opens as the user left it.
public struct PaneLayout: Codable, Equatable, Sendable {
    static let projectsWidths: ClosedRange<Double> = 160...360
    static let sessionsWidths: ClosedRange<Double> = 240...520
    static let defaultsKey = "MainWindowPaneLayout"

    public var projectsWidth: Double = 210
    public var sessionsWidth: Double = 300
    public var projectsHidden = false
    public var sessionsHidden = false

    public init() {}

    /// The layout with each width inside its limits, as a drag leaves it.
    func clamped() -> PaneLayout {
        var layout = self
        layout.projectsWidth = min(max(projectsWidth, Self.projectsWidths.lowerBound), Self.projectsWidths.upperBound)
        layout.sessionsWidth = min(max(sessionsWidth, Self.sessionsWidths.lowerBound), Self.sessionsWidths.upperBound)
        return layout
    }

    /// The narrowest window: the smallest width of each visible list, and the
    /// minimum width of the content of the third pane.
    func minimumWidth(content: Double) -> Double {
        (projectsHidden ? 0 : Self.projectsWidths.lowerBound) + (sessionsHidden ? 0 : Self.sessionsWidths.lowerBound) + content
    }

    /// The kept layout, or the first layout when there is none or it cannot be read.
    static func load(from defaults: UserDefaults) -> PaneLayout {
        guard let data = defaults.data(forKey: defaultsKey), let layout = try? JSONDecoder().decode(PaneLayout.self, from: data) else {
            return PaneLayout()
        }
        return layout.clamped()
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
