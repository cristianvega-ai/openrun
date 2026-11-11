import AppKit
import TerminalEmulation

/// The small label that names the part of a grid that the pane hides, such
/// as "40 rows hidden" (answer of the owner of 2026-10-27). The grid stays at
/// the top left, so the hidden part is at the bottom and at the right.
@MainActor
final class HiddenGridLabel: NSTextField {
    static func text(grid: TerminalSize, visible: TerminalSize) -> String? {
        let parts = [(Int(grid.rows) - Int(visible.rows), "row"), (Int(grid.columns) - Int(visible.columns), "column")]
            .compactMap { count, name in count > 0 ? "\(count) \(name)\(count == 1 ? "" : "s")" : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " and ") + " hidden"
    }

    init() {
        super.init(frame: .zero)
        (isEditable, isSelectable, isBordered, drawsBackground) = (false, false, false, true)
        (font, textColor, backgroundColor, alignment) = (.systemFont(ofSize: NSFont.smallSystemFontSize), .secondaryLabelColor, .windowBackgroundColor, .center)
        wantsLayer = true
        layer?.cornerRadius = 4
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("HiddenGridLabel does not come from a storyboard.")
    }

    /// Room around the text, so the label reads as a badge over the grid.
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 12, height: size.height + 4)
    }

    func show(grid: TerminalSize, visible: TerminalSize) {
        stringValue = Self.text(grid: grid, visible: visible) ?? ""
        isHidden = stringValue.isEmpty
    }
}
