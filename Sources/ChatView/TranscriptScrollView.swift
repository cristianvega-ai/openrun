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
    private var lastClipSize = NSSize.zero

    init(transcriptView: TranscriptView) {
        self.transcriptView = transcriptView
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
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
    }

    private func setFollowing(_ isFollowing: Bool) {
        guard transcriptView.isFollowingBottom != isFollowing else { return }
        transcriptView.isFollowingBottom = isFollowing
        followingChanged?(isFollowing)
    }
}
