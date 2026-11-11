import AppKit

/// The lines of a diff, drawn one by one. An added or removed line has a
/// quiet fill across the whole box, and a mark in the margin, so the change
/// reads without color too.
final class DiffLinesView: NSView {
    private var lines: [UnifiedDiff.Line] = []
    private var note: String?
    private var palette: ChatPalette?
    private(set) var lineHeight: CGFloat = 17
    /// The width of the longest line.
    private(set) var contentWidth: CGFloat = 0
    static let textOffset: CGFloat = 30

    override var isFlipped: Bool { true }

    func show(_ shownLines: [UnifiedDiff.Line], note newNote: String?, palette newPalette: ChatPalette) {
        lines = shownLines
        note = newNote
        palette = newPalette
        lineHeight = ceil(newPalette.smallCodeFont.ascender - newPalette.smallCodeFont.descender + 4)
        let attributes: [NSAttributedString.Key: Any] = [.font: newPalette.smallCodeFont]
        contentWidth = lines.reduce(0) { max($0, ceil(String($1.text).size(withAttributes: attributes).width)) } + Self.textOffset + 12
        needsDisplay = true
    }

    var contentHeight: CGFloat {
        CGFloat(lines.count + (note == nil ? 0 : 1)) * lineHeight
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette else { return }
        let first = max(0, Int(dirtyRect.minY / lineHeight))
        let last = min(lines.count, Int(dirtyRect.maxY / lineHeight) + 1)
        let code: [NSAttributedString.Key: Any] = [.font: palette.smallCodeFont, .foregroundColor: palette.text]
        let quiet: [NSAttributedString.Key: Any] = [.font: palette.smallCodeFont, .foregroundColor: palette.secondaryText]
        for index in first..<max(first, last) {
            let line = lines[index]
            let rect = NSRect(x: 0, y: CGFloat(index) * lineHeight, width: bounds.width, height: lineHeight)
            let (fill, mark): (NSColor?, String) = switch line.kind {
            case .added: (palette.addedLineBackground, "+")
            case .removed: (palette.removedLineBackground, "\u{2212}")
            case .hunk, .context: (nil, "")
            }
            if let fill {
                fill.setFill()
                rect.fill()
            }
            let y = rect.minY + 2
            mark.draw(at: NSPoint(x: 12, y: y), withAttributes: quiet)
            String(line.text).draw(at: NSPoint(x: line.kind == .hunk ? 12 : Self.textOffset, y: y), withAttributes: line.kind == .hunk ? quiet : code)
        }
        if let note, last == lines.count {
            let font = palette.smallFont
            note.draw(at: NSPoint(x: 12, y: CGFloat(lines.count) * lineHeight + 2), withAttributes: [.font: font, .foregroundColor: palette.secondaryText])
        }
    }
}
