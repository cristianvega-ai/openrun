import AppKit
import PseudoTerminal
import SessionProcessHarness
import Testing
import WindowLayout
@testable import BrowserPane
@testable import OpenRunApplication

/// The web page in a split of the third pane. No test uses the network.
@MainActor @Suite(.serialized) struct WorkspaceBrowserTests {
    /// A started workspace with one shell in the third pane.
    private func start() async throws -> (test: TestWorkspace, first: UUID) {
        let test = try TestWorkspace()
        let folder = test.process.directory.path
        (test.workspace.home, test.workspace.loginShell) = (folder, LoginShell(path: "/bin/sh"))
        test.workspace.sessionEnvironment = ["HOME": folder, "PATH": "/usr/bin:/bin", "PS1": "test> "]
        test.workspace.start()
        #expect(await waitUntil { test.workspace.connection.hasSessionList })
        test.workspace.newSession()
        #expect(await waitUntil { test.workspace.shownSession.flatMap { test.workspace.panes.existing($0)?.terminalView } != nil })
        return (test, try #require(test.workspace.shownSession))
    }

    @Test func aWebPageOfTheLayoutShowsBesideThePaneAndKeepsItsAddress() async throws {
        let (test, first) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        let page = LayoutBrowser(address: BrowserAddress.blank)
        workspace.layout.addBrowser(page, beside: first, direction: .sideBySide)
        (workspace.leafToFocus, workspace.lastFocusedLeaf) = (page.identifier, page.identifier)
        workspace.refresh()
        let browser = try #require(workspace.browserPanes[page.identifier])
        // The row keeps its place, and the page shows beside the terminal with the focus in its address.
        #expect(workspace.layout.rows.first?.pane.leaves == [first, page.identifier] && test.shownRows == [first])
        let (split, view) = (try #require(workspace.splitView), try #require(workspace.splitView?.view(of: page.identifier)))
        #expect(view === browser.view && view.window === workspace.window.window && view.frame.width > 300 && workspace.focusedLeaf == page.identifier)
        browser.webView.loadHTMLString("<p>Hello</p>", baseURL: URL(string: "http://localhost:3000/docs"))
        #expect(await waitUntil { workspace.layout.browser(page.identifier)?.address == "http://localhost:3000/docs" })
        // The pane keeps its views, and the file of the layout has the address.
        #expect(workspace.splitView === split && workspace.shown == .split(row: first, pane: try #require(workspace.layout.rows.first?.pane)))
        #expect(await waitUntil { workspace.layoutStore.load().browser(page.identifier)?.address == "http://localhost:3000/docs" })
    }
}
