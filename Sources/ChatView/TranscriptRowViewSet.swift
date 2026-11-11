import AppKit

/// The views of the rows near the screen. A row far from the screen has no
/// view, so a transcript of any length needs only a few views.
@MainActor struct TranscriptRowViewSet {
    private(set) var views: [String: TranscriptRowView] = [:]
    /// The rows whose view must show new content.
    private var changedKeys: Set<String> = []

    /// Records the rows whose content changed.
    mutating func markChanged(_ keys: Set<String>) {
        changedKeys.formUnion(keys.filter { views[$0] != nil })
    }

    /// The view of `row`. A new view goes into `container`, and a view
    /// shows its row again when the row changed.
    mutating func view(for row: TranscriptRow, context: TranscriptRowContext, in container: NSView) -> TranscriptRowView {
        if let view = views[row.key] {
            if changedKeys.remove(row.key) != nil || view.row != row { view.configure(row, context: context) }
            return view
        }
        let view = TranscriptRowViews.make(for: row)
        view.configure(row, context: context)
        views[row.key] = view
        container.addSubview(view)
        return view
    }

    /// Removes the views of the rows that `isKept` rejects.
    mutating func removeViews(keeping isKept: (String) -> Bool) {
        for (key, view) in views where !isKept(key) {
            view.removeFromSuperview()
            views[key] = nil
            changedKeys.remove(key)
        }
    }
}
