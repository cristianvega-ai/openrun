import AppKit
import Testing
@testable import PaneAppearance

@MainActor @Suite struct OverlayScrollViewTests {
    /// AppKit sets legacy scrollers on each scroll view when the user asks
    /// for them, and the lists keep thin overlay scrollers.
    @Test func theScrollersStayOverlay() {
        let scroll = OverlayScrollView()
        scroll.scrollerStyle = .legacy
        #expect(scroll.scrollerStyle == .overlay)
    }
}
