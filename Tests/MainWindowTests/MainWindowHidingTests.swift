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
        #expect(controller.projectsList.topRow.leadingSpace == lights && controller.sessionsList.topRow.leadingSpace == 16)
        controller.toggleProjectsList(nil)
        #expect(controller.projectsItem.isCollapsed && controller.sessionsList.topRow.leadingSpace == lights)
        controller.toggleSessionsList(nil)
        #expect(controller.sessionsItem.isCollapsed && controller.contentPane.topRow.leadingSpace == lights)
        controller.window.close()
        let next = makeMainWindow(defaults: defaults)
        defer { next.window.close() }
        #expect(next.projectsItem.isCollapsed && next.sessionsItem.isCollapsed && next.contentPane.topRow.leadingSpace == lights)
        next.reducesMotion = { true }
        next.toggleProjectsList(nil)
        #expect(!next.projectsItem.isCollapsed && next.contentPane.topRow.leadingSpace == 16 && !PaneLayout.load(from: defaults).projectsHidden)
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
