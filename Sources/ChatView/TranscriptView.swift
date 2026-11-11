import AppKit

/// The document view of the transcript: a column of rows of which only
/// those near the screen have a view.
///
/// It measures a row when the row comes near the screen, and it keeps the
/// row that the user reads at the same place when rows above it change
/// their height, so nothing jumps. While the user is at the bottom, it
/// follows the newest row instead.
@MainActor final class TranscriptView: NSView {
    let context: TranscriptRowContext
    private(set) var rows: [TranscriptRow] = []
    private(set) var rowLayout = RowLayout()
    private var spacings: [CGFloat] = []
    private(set) var rowViews = TranscriptRowViewSet()
    private var measuredWidth: CGFloat = -1
    /// Whether the view moves its rows now. A move of the screen then is
    /// not a scroll of the user.
    private(set) var isTiling = false
    /// Whether the view keeps the newest row in sight.
    var isFollowingBottom = true
    /// Runs after the views of the rows near the screen change.
    var viewsPlaced: (() -> Void)?
    /// A row whose top stays where it is on the screen at the next tile.
    private var pinnedAnchor: RowLayout.Anchor?

    override var isFlipped: Bool { true }

    init(context: TranscriptRowContext) {
        self.context = context
        super.init(frame: .zero)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Conversation")
    }

    /// The rows in the order of the conversation. The views come and go
    /// as the user scrolls, so the order of the subviews is not the order
    /// that VoiceOver must read.
    override func accessibilityChildren() -> [Any]? {
        subviews.filter { !$0.isHidden }.sorted { $0.frame.minY < $1.frame.minY }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Takes the rows as they are now.
    /// - Parameter changed: The keys of rows whose content changed.
    func setRows(_ newRows: [TranscriptRow], changed: Set<String>) {
        var changedKeys = changed
        var newSpacings: [CGFloat] = []
        newSpacings.reserveCapacity(newRows.count)
        for (index, row) in newRows.enumerated() {
            let spacing = RowSpacing.above(row, after: index > 0 ? newRows[index - 1] : nil)
            if let old = rowLayout.index(of: row.key), spacings[old] != spacing { changedKeys.insert(row.key) }
            newSpacings.append(spacing)
        }
        rowViews.markChanged(changedKeys)
        let width = max(measuredWidth, 0)
        rowLayout.update(keys: newRows.map(\.key), changed: changedKeys) { index in
            newSpacings[index] + RowEstimate.height(of: newRows[index], width: width, context: context)
        }
        rows = newRows
        spacings = newSpacings
        rowViews.removeViews { rowLayout.index(of: $0) != nil }
        tile()
    }

    /// Shows a row again after the user opened or closed a part of it. The
    /// top of the row stays where it is on the screen, so what the user
    /// reads does not move.
    func keepInPlace(_ key: String) {
        guard let index = rowLayout.index(of: key), let clip = enclosingScrollView?.contentView else { return }
        pinnedAnchor = RowLayout.Anchor(key: key, offset: clip.bounds.minY - rowLayout.top(of: index))
        setRows(rows, changed: [key])
    }

    /// The top of a row in the document, or nil when no row has the key.
    func top(ofRow key: String) -> CGFloat? {
        rowLayout.index(of: key).map { rowLayout.top(of: $0) }
    }

    /// Measures the rows near the screen, sets the height of the document,
    /// keeps the place of what the user reads, and places the views.
    func tile() {
        guard !isTiling, let scrollView = enclosingScrollView else { return }
        isTiling = true
        defer { isTiling = false }
        let clip = scrollView.contentView
        let width = clip.bounds.width
        if width != measuredWidth {
            measuredWidth = width
            rowLayout.forgetMeasurements()
        }
        let viewport = clip.bounds.height
        let anchor = pinnedAnchor ?? (isFollowingBottom ? nil : rowLayout.anchor(at: clip.bounds.minY))
        pinnedAnchor = nil
        let origin = rowLayout.settle(keeping: anchor, viewport: viewport, bottomPadding: RowSpacing.bottom) { index in
            spacings[index] + rowViews.view(for: rows[index], context: context, in: self).height(forWidth: width)
        }
        let size = NSSize(width: width, height: max(viewport, rowLayout.totalHeight() + RowSpacing.bottom))
        if frame.size != size { setFrameSize(size) }
        if clip.bounds.minY != origin {
            clip.scroll(to: NSPoint(x: 0, y: origin))
            scrollView.reflectScrolledClipView(clip)
        }
        placeViews(near: origin, viewport: viewport, width: width)
        viewsPlaced?()
    }

    private func placeViews(near origin: CGFloat, viewport: CGFloat, width: CGFloat) {
        let range = rowLayout.rows(near: origin, viewport: viewport)
        rowViews.removeViews { key in rowLayout.index(of: key).map { range?.contains($0) == true } ?? false }
        guard let range else { return }
        for index in range {
            let view = rowViews.view(for: rows[index], context: context, in: self)
            let top = rowLayout.top(of: index) + spacings[index]
            let frame = NSRect(x: 0, y: top, width: width, height: rowLayout.heights[index] - spacings[index])
            if view.frame != frame {
                view.frame = frame
                view.needsLayout = true
            }
        }
    }
}
