import AppKit
import Testing
@testable import MainWindow
@testable import SessionPane

/// A change of the widths of the panes gives a session one size, at the end.
@MainActor @Suite(.serialized) struct MainWindowResizeTests {
    @Test func oneAnimatedToggleSendsOneSize() async throws {
        try await withHostedSession { controller, pane in
            let before = pane.sentSizeRequests
            for count in 1...2 {
                controller.toggleProjectsList(nil)
                await turns(seconds: 20) { pane.sentSizeRequests >= before + count }
                await turns(seconds: 0.5)
                #expect(pane.sentSizeRequests == before + count)
                #expect(pane.paneView.frame.width == controller.contentPane.contentArea.frame.width)
            }
        }
    }

    @Test func aDragOfAnEdgeSendsOneSize() async throws {
        try await withHostedSession { controller, pane in
            let before = pane.sentSizeRequests
            try dragSessionsEdge(of: controller, by: 96)
            await turns(seconds: 20) { pane.sentSizeRequests > before }
            await turns(seconds: 0.5)
            #expect(abs(controller.sessionsList.view.frame.width - 396) < 2)
            #expect(pane.sentSizeRequests == before + 1)
            #expect(pane.paneView.frame.width == controller.contentPane.contentArea.frame.width)
        }
    }

    /// Two animations that overlap end the hold once, at the end of the last.
    @Test func bothListsTogetherSendOneSize() async throws {
        try await withHostedSession { controller, pane in
            for count in 1...2 {
                controller.toggleProjectsList(nil)
                controller.toggleSessionsList(nil)
                await turns(seconds: 5) { !controller.contentPane.isHoldingWidth }
                await turns(seconds: 0.5)
                #expect(pane.sentSizeRequests == count)
                #expect(pane.paneView.frame.width == controller.contentPane.contentArea.frame.width)
            }
        }
    }
}
