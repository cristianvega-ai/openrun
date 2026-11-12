import AppKit
import WindowLayout

/// The view of a row with splits (decision of 2026-11-10): the views of
/// its sessions and threads, side by side or one over the other as the
/// layout tells, with a thin divider between two halves.
///
/// The view owns no session. Its host gives the view of each leaf and
/// hears of a divider that the user moved.
@MainActor public final class SplitPaneView: NSView {
    public let pane: LayoutPane
    private var leafViews: [UUID: NSView] = [:]
    /// Tells the new share of the first half of a split, by the leaf that
    /// starts its second half, after the user moved the divider.
    public var fractionChanged: ((_ leaf: UUID, _ fraction: Double) -> Void)?

    /// - Parameter leafView: The view of a session or a thread of the pane.
    public init(pane: LayoutPane, leafView: (UUID) -> NSView) {
        self.pane = pane
        super.init(frame: .zero)
        let root = build(pane, leafView)
        root.frame = bounds
        root.autoresizingMask = [.width, .height]
        addSubview(root)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build(_ pane: LayoutPane, _ leafView: (UUID) -> NSView) -> NSView {
        switch pane {
        case .session, .thread, .browser:
            guard let identifier = pane.leaves.first else { return NSView() }
            let view = leafView(identifier)
            leafViews[identifier] = view
            return view
        case .split(let split):
            let halves = HalvesView(split: split, first: build(split.first, leafView), second: build(split.second, leafView))
            let leaf = split.second.leaves.first
            halves.fractionChanged = { [weak self] fraction in leaf.map { self?.fractionChanged?($0, fraction) } }
            return halves
        }
    }

    public func view(of leaf: UUID) -> NSView? {
        leafViews[leaf]
    }

    /// The leaf whose view holds `view`, such as the view with the keyboard focus.
    public func leaf(holding view: NSView?) -> UUID? {
        guard let view else { return nil }
        return leafViews.first { view === $0.value || view.isDescendant(of: $0.value) }?.key
    }

    /// The smallest size of a pane, from the smallest size of each leaf:
    /// two halves side by side add their widths, and two stacked halves
    /// add their heights, each with the divider between them.
    public static func minimumSize(of pane: LayoutPane, leaf: (UUID) -> CGSize) -> CGSize {
        switch pane {
        case .session, .thread, .browser:
            return pane.leaves.first.map(leaf) ?? .zero
        case .split(let split):
            let (first, second) = (minimumSize(of: split.first, leaf: leaf), minimumSize(of: split.second, leaf: leaf))
            let divider = HalvesView.dividerWidth
            return split.direction == .sideBySide
                ? CGSize(width: first.width + second.width + divider, height: max(first.height, second.height))
                : CGSize(width: max(first.width, second.width), height: first.height + second.height + divider)
        }
    }
}
