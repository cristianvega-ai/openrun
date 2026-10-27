import GhosttyVt

extension Terminal {
    /// Moves the visible rows. Output moves them back to the bottom only
    /// while `isViewportAtBottom` is `true`, so the view stays where the
    /// user scrolled to.
    public func scrollViewport(_ scroll: ViewportScroll) {
        var behavior = GhosttyTerminalScrollViewport()
        switch scroll {
        case .toTop: behavior.tag = GHOSTTY_SCROLL_VIEWPORT_TOP
        case .toBottom: behavior.tag = GHOSTTY_SCROLL_VIEWPORT_BOTTOM
        case .byRows(let rows):
            behavior.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA
            behavior.value.delta = rows
        case .toRow(let row):
            behavior.tag = GHOSTTY_SCROLL_VIEWPORT_ROW
            behavior.value.row = max(row, 0)
        }
        ghostty_terminal_scroll_viewport(handle, behavior)
    }

    public var scrollbar: Scrollbar {
        var bar = GhosttyTerminalScrollbar()
        _ = ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &bar)
        return Scrollbar(totalRows: bar.total, firstVisibleRow: bar.offset, visibleRows: bar.len)
    }

    /// Whether the visible rows follow the output, that is, the user has not
    /// scrolled up.
    public var isViewportAtBottom: Bool {
        var active = true
        _ = ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_VIEWPORT_ACTIVE, &active)
        return active
    }
}
