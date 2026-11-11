import AppKit
import Testing
@testable import MainWindow

/// Full screen hides the traffic lights, so the first visible top row
/// uses their room until full screen ends.
@MainActor @Suite struct MainWindowFullScreenTests {
    private func post(_ name: Notification.Name, _ controller: MainWindowController) {
        NotificationCenter.default.post(name: name, object: controller.window)
    }

    @Test func fullScreenGivesTheRoomOfTheLightsToTheFirstTopRow() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        let lights = controller.paneWindow.trafficLightsSpace
        post(NSWindow.willEnterFullScreenNotification, controller)
        #expect(controller.projectsList.topRow.leadingSpace == 16)
        controller.toggleProjectsList(nil)
        #expect(controller.sessionsList.topRow.leadingSpace == 16)
        post(NSWindow.willExitFullScreenNotification, controller)
        #expect(controller.sessionsList.topRow.leadingSpace == lights)
        post(NSWindow.willEnterFullScreenNotification, controller)
        controller.windowDidFailToEnterFullScreen(controller.window)
        #expect(controller.sessionsList.topRow.leadingSpace == lights)
    }
}
