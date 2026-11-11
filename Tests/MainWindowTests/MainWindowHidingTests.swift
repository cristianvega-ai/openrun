import AppKit
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
        #expect(items.map(\.title) == ["Hide Projects", "Hide Sessions"] && items.allSatisfy { $0.keyEquivalentModifierMask == [.command, .control] })
        controller.toggleSessionsList(nil)
        _ = items.map(controller.validateMenuItem)
        #expect(items.map(\.title) == ["Hide Projects", "Show Sessions"])
    }
}
