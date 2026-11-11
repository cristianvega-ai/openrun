import AppKit

/// The top row of a pane. The window has no title strip, so the top rows of
/// the three panes take its place: they have one height, the traffic lights
/// sit in the top row of the first pane, and the window drags from the empty
/// parts of each row (decision of 2026-10-26).
@MainActor
public final class PaneTopRow: NSView {
    /// The height of the unified toolbar of macOS, whose middle the traffic
    /// lights take, so that the controls of each row line up with them.
    public static let height: CGFloat = 52
    /// The controls at the start of the row, centered on its middle line.
    public let leadingItems = NSStackView()
    /// The controls at the end of the row.
    public let trailingItems = NSStackView()
    private let background: NSColor
    private var leadingInset: NSLayoutConstraint?

    /// - Parameter background: The color of the pane that the row belongs to.
    public init(background: NSColor) {
        self.background = background
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
        for stack in [leadingItems, trailingItems] {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            stack.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        leadingItems.setHuggingPriority(.defaultLow, for: .horizontal)
        leadingInset = leadingItems.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([
            leadingInset!,
            trailingItems.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            leadingItems.trailingAnchor.constraint(lessThanOrEqualTo: trailingItems.leadingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PaneTopRow does not come from a storyboard.")
    }

    /// The space before the leading controls, such as the room of the traffic lights.
    public var leadingSpace: CGFloat {
        get { leadingInset?.constant ?? 0 }
        set { leadingInset?.constant = newValue }
    }

    public override var isOpaque: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }

    /// Views do not clip to their bounds since macOS 14, so the dirty
    /// rectangle can reach past the row and over the list below it.
    public override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        dirtyRect.intersection(bounds).fill()
    }

    /// A press on an empty part moves the window, and a double click does
    /// what the user chose in System Settings for a double click on a title bar.
    public override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}
