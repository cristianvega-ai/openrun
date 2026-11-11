import AppKit

/// The scroll view of a list. It keeps thin overlay scrollers when the user
/// asks for legacy ones, because a wide legacy scroller takes room from the
/// rows and its track breaks the calm color of the pane.
@MainActor
public final class OverlayScrollView: NSScrollView {
    public override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}
