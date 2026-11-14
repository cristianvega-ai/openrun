import AppKit

/// A control with one segment for each value of a setting, for a choice
/// of a few short values, so the user sees all of them at once.
@MainActor final class SegmentSettingControl: NSObject, SettingControl {
    let segments: NSSegmentedControl
    private let values: [String]
    var changed: ((String) -> Void)?
    var view: NSView { segments }

    init(_ choices: [(value: String, title: String)]) {
        values = choices.map(\.value)
        segments = NSSegmentedControl(labels: choices.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        super.init()
        (segments.target, segments.action) = (self, #selector(choose))
    }

    func show(_ text: String) {
        // A value of a later build selects no segment, so the window never shows a wrong value.
        segments.selectedSegment = values.firstIndex(of: text) ?? -1
    }

    @objc func choose() {
        guard values.indices.contains(segments.selectedSegment) else { return }
        changed?(values[segments.selectedSegment])
    }
}
