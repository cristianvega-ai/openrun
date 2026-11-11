import AppKit

/// The scroll view of the transcript. It tells the transcript view when the
/// user scrolls, and whether the user is at the bottom.
@MainActor final class TranscriptScrollView: NSScrollView {
    /// How close to the bottom the user must be for the view to follow
    /// the newest row.
    static let bottomTolerance: CGFloat = 8
    let transcriptView: TranscriptView
    /// Tells when the user leaves the bottom or comes back to it.
    var followingChanged: ((Bool) -> Void)?
    /// Tells when the user scrolls to the top.
    var reachedTop: (() -> Void)?
    private var lastClipSize = NSSize.zero

    init(transcriptView: TranscriptView) {
        self.transcriptView = transcriptView
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        // Under the title bar of a window, AppKit would add an inset and
        // move the rows. That move has the look of a scroll of the user,
        // and the view would stop to follow the newest row.
        automaticallyAdjustsContentInsets = false
        contentView.drawsBackground = false
        documentView = transcriptView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsDidChange), name: NSView.boundsDidChangeNotification, object: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var distanceFromBottom: CGFloat {
        transcriptView.frame.height - contentView.bounds.maxY
    }

    /// Goes to the newest row and follows it again.
    func scrollToNewest() {
        setFollowing(true)
        transcriptView.tile()
    }

    /// Scrolls a row to a third of the way down the screen and returns its
    /// view, as for a match of Find.
    func reveal(_ key: String) -> TranscriptRowView? {
        guard let top = transcriptView.top(ofRow: key) else { return nil }
        let maximum = max(0, transcriptView.frame.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, top - contentView.bounds.height / 3))))
        reflectScrolledClipView(contentView)
        return transcriptView.rowViews.views[key]
    }

    /// Shows a row again after the user opened or closed a part of it,
    /// and stops the follow when the bottom went out of sight.
    func keepInPlace(_ key: String) {
        transcriptView.keepInPlace(key)
        setFollowing(distanceFromBottom <= Self.bottomTolerance)
    }

    override func layout() {
        super.layout()
        transcriptView.tile()
    }

    @objc private func boundsDidChange() {
        // A new size of the pane is no scroll of the user.
        let isNewSize = contentView.bounds.size != lastClipSize
        lastClipSize = contentView.bounds.size
        guard !transcriptView.isTiling else { return }
        guard !isNewSize else {
            transcriptView.tile()
            return
        }
        // Only the user moves the view outside a tile, so this is where the
        // view starts or stops to follow the newest row.
        setFollowing(distanceFromBottom <= Self.bottomTolerance)
        transcriptView.tile()
        if contentView.bounds.minY < 60 { reachedTop?() }
    }

    private func setFollowing(_ isFollowing: Bool) {
        guard transcriptView.isFollowingBottom != isFollowing else { return }
        transcriptView.isFollowingBottom = isFollowing
        followingChanged?(isFollowing)
    }
}
