import AppKit
import PaneAppearance
import Testing
@testable import MainWindow

@MainActor @Suite struct MainWindowHidingTests {
    @Test func theListsHideAndShowAndTheNextStartKeepsThem() {
        let defaults = temporaryDefaults()
        let controller = makeMainWindow(defaults: defaults)
        controller.reducesMotion = { true }
        let lights = controller.paneWindow.trafficLightsSpace
        #expect(leadingRoom(of: controller.projectsList.topRow, in: controller) == lights && leadingRoom(of: controller.sessionsList.topRow, in: controller) == 16)
        controller.toggleProjectsList(nil)
        #expect(controller.projectsItem.isCollapsed && leadingRoom(of: controller.sessionsList.topRow, in: controller) == lights)
        controller.toggleSessionsList(nil)
        #expect(controller.sessionsItem.isCollapsed && leadingRoom(of: controller.contentPane.topRow, in: controller) == lights)
        controller.window.close()
        let next = makeMainWindow(defaults: defaults)
        defer { next.window.close() }
        #expect(next.projectsItem.isCollapsed && next.sessionsItem.isCollapsed && leadingRoom(of: next.contentPane.topRow, in: next) == lights)
        next.reducesMotion = { true }
        next.toggleProjectsList(nil)
        #expect(!next.projectsItem.isCollapsed && leadingRoom(of: next.contentPane.topRow, in: next) == 16 && !PaneLayout.load(from: defaults).projectsHidden)
    }

    /// A list hides only through its button, its menu command and its key.
    /// A drag of an edge stops at the minimum width of the list.
    @Test func aDragPastTheMinimumKeepsTheListAtItsMinimum() throws {
        let defaults = temporaryDefaults()
        let controller = makeMainWindow(defaults: defaults)
        defer { controller.window.close() }
        let splitView = try #require(controller.splitController.splitView as? PaneSplitView)
        // The sessions list goes first, so it has room to grow when the projects list shrinks.
        for edge in [1, 0] {
            let list = edge == 0 ? controller.projectsList.view : controller.sessionsList.view
            let item = edge == 0 ? controller.projectsItem : controller.sessionsItem
            splitView.dragStarted?()
            splitView.setPosition(edge == 0 ? 0 : controller.frame(of: list).minX, ofDividerAt: edge)
            controller.window.layoutIfNeeded()
            splitView.dragEnded?()
            let saved = PaneLayout.load(from: defaults)
            #expect(!controller.projectsItem.isCollapsed && !controller.sessionsItem.isCollapsed, "edge \(edge)")
            #expect(list.frame.width == item.minimumThickness && !saved.projectsHidden && !saved.sessionsHidden, "edge \(edge)")
            #expect(!controller.layout.projectsHidden && !controller.layout.sessionsHidden, "edge \(edge)")
            #expect(controller.window.contentMinSize.width == expectedMinimumWidth(of: controller, content: 360), "edge \(edge)")
        }
    }

    @Test func theMenuItemsSayWhatTheyDoNow() throws {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        let items = controller.paneMenuItems()
        #expect(items.map(\.title) == ["Hide Projects", "Hide Sessions", "Move Focus to Next Pane", "Move Focus to Previous Pane"])
        #expect(items.prefix(2).allSatisfy { $0.keyEquivalentModifierMask == [.command, .control] })
        controller.toggleSessionsList(nil)
        _ = items.map(controller.validateMenuItem)
        #expect(items.prefix(2).map(\.title) == ["Hide Projects", "Show Sessions"])
    }

    /// With both lists hidden, the button still shows the way back.
    @Test func theListsButtonSitsFirstInTheFirstVisibleTopRow() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        func firstItem(of row: PaneTopRow) -> NSView? { row.leadingItems.arrangedSubviews.first }
        #expect(firstItem(of: controller.projectsList.topRow) === controller.listsButton)
        controller.toggleSessionsList(nil)
        #expect(firstItem(of: controller.projectsList.topRow) === controller.listsButton)
        controller.toggleProjectsList(nil)
        #expect(firstItem(of: controller.contentPane.topRow) === controller.listsButton)
        #expect(controller.listsButton.toolTip == "Show Projects")
        controller.toggleSessionsList(nil)
        #expect(firstItem(of: controller.sessionsList.topRow) === controller.listsButton)
        controller.listsButton.performClick(nil)
        #expect(!controller.projectsItem.isCollapsed && firstItem(of: controller.projectsList.topRow) === controller.listsButton)
        #expect(controller.listsButton.toolTip == "Hide Projects" && firstItem(of: controller.sessionsList.topRow) !== controller.listsButton)
    }
}
