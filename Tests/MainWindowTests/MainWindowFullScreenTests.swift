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
        #expect(leadingRoom(of: controller.projectsList.topRow, in: controller) == 16)
        controller.toggleProjectsList(nil)
        #expect(leadingRoom(of: controller.sessionsList.topRow, in: controller) == 16)
        post(NSWindow.willExitFullScreenNotification, controller)
        #expect(leadingRoom(of: controller.sessionsList.topRow, in: controller) == lights)
        post(NSWindow.willEnterFullScreenNotification, controller)
        controller.windowDidFailToEnterFullScreen(controller.window)
        #expect(leadingRoom(of: controller.sessionsList.topRow, in: controller) == lights)
    }
}
