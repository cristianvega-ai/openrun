import AppKit
import Foundation
import PaneAppearance
import Testing
@testable import MainWindow

/// Defaults of their own for one test, so no test reads or changes the app's.
func temporaryDefaults() -> UserDefaults {
    let name = "MainWindowTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// A main window that keeps no frame, with its layout in temporary defaults.
@MainActor
func makeMainWindow(defaults: UserDefaults = temporaryDefaults()) -> MainWindowController {
    _ = NSApplication.shared
    let controller = MainWindowController(defaults: defaults, frameName: nil)
    controller.window.setContentSize(NSSize(width: 1_100, height: 700))
    controller.window.layoutIfNeeded()
    return controller
}

/// Drags the edge between the sessions list and the third pane in twelve
/// steps. A real drag runs in the tracking loop of mouseDown, which ended
/// the test process when an async test ran beside it, so the steps call
/// the drag hooks of the split view and then move the edge.
@MainActor
func dragSessionsEdge(of controller: MainWindowController, by distance: CGFloat) throws {
    let splitView = try #require(controller.splitController.splitView as? PaneSplitView)
    let start = controller.frame(of: controller.contentPane.view).minX - splitView.dividerThickness
    splitView.dragStarted?()
    for step in 1...12 {
        splitView.setPosition(start + distance * CGFloat(step) / 12, ofDividerAt: 1)
        controller.window.layoutIfNeeded()
    }
    splitView.dragEnded?()
}

/// The narrowest window: each visible list at its limit, or at the width
/// that its top row needs when that is more, with its divider, and the content.
@MainActor
func expectedMinimumWidth(of controller: MainWindowController, content: CGFloat) -> CGFloat {
    let divider = controller.splitController.splitView.dividerThickness
    // The first visible list keeps the room of the traffic lights in its top row.
    let lights = controller.paneWindow.trafficLightsSpace - 16
    let (projects, sessions) = (!controller.projectsItem.isCollapsed, !controller.sessionsItem.isCollapsed)
    var width = content
    if projects { width += max(160, controller.projectsList.topRow.fittingSize.width + lights) + divider }
    if sessions { width += max(240, controller.sessionsList.topRow.fittingSize.width + (projects ? 0 : lights)) + divider }
    return width
}

/// AppKit moves the panes in an animation only while the display refreshes,
/// so a test that waits for an animation needs a display that is awake and
/// not locked.
func displayIsLive() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    let isLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    return !isLocked && CGDisplayIsAsleep(CGMainDisplayID()) == 0
}

extension Trait where Self == ConditionTrait {
    static var needsLiveDisplay: Self {
        .enabled("An animation of AppKit needs a display that is awake and not locked") { displayIsLive() }
    }
}

/// The room before the controls of a top row, from the left edge of its
/// pane. The first visible row keeps the room of the traffic lights.
@MainActor
func leadingRoom(of row: PaneTopRow, in controller: MainWindowController) -> CGFloat {
    controller.window.layoutIfNeeded()
    return row.leadingItems.frame.minX
}
