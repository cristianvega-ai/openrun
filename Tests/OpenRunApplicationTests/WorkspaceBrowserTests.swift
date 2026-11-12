import AppKit
import PseudoTerminal
import SessionConnection
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

    @Test func aWebPageOpensBesideThePaneAndKeepsItsAddressInTheLayout() async throws {
        let (test, first) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        #expect(workspace.validateMenuItem(NSMenuItem(title: "", action: #selector(Workspace.splitWithBrowser(_:)), keyEquivalent: "")))
        workspace.splitWithBrowser(nil)
        let page = try #require(workspace.layout.rows.first?.pane.browsers.first)
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

    /// The links go to a port of this Mac on which no program listens.
    @Test func aWebLinkOpensInAWebPageOfItsRowWhenTheSettingAsksForIt() async throws {
        let (test, first) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        let (link, next) = (try #require(URL(string: "http://127.0.0.1:9/docs")), try #require(URL(string: "http://127.0.0.1:9/next")))
        // With the usual setting, the link goes to the default program.
        #expect(!workspace.openInBrowserSplit(link, from: first) && workspace.browserPanes.isEmpty)
        try SessionClient(location: workspace.socket).changeSetting(named: "open-links-in", to: "browser-split")
        #expect(await waitUntil { workspace.settings.linkDestination == .browserSplit })
        // The terminal view gives its web links to the host, and the focus stays in the terminal.
        #expect(workspace.panes.existing(first)?.terminalView?.webLinkAction?(link) == true)
        let page = try #require(workspace.layout.rows.first?.pane.browsers.first)
        #expect(page.address == link.absoluteString && workspace.layout.rows.first?.pane.leaves == [first, page.identifier])
        #expect(workspace.browserPanes[page.identifier] != nil && workspace.focusedLeaf == first)
        // The next link uses the page of the row, and a link that is no web address does not.
        #expect(workspace.openInBrowserSplit(next, from: first) && !workspace.openInBrowserSplit(URL(fileURLWithPath: "/etc/hosts"), from: first))
        #expect(await waitUntil { workspace.layout.browser(page.identifier)?.address == next.absoluteString })
        #expect(workspace.layout.rows.first?.pane.browsers.count == 1)
    }

    @Test func commandWClosesAWebPageAndTheEndOfItsRowForgetsIt() async throws {
        let (test, first) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.splitWithBrowser(nil)
        #expect(workspace.browserPanes.count == 1 && workspace.focusedLeaf != first)
        workspace.closeSession(nil)
        #expect(workspace.shown == .session(first) && workspace.browserPanes.isEmpty && workspace.layout.rows.first?.pane == .session(first))
        // A web page alone is no row: it goes with the last session of its row.
        workspace.splitWithBrowser(nil)
        #expect(workspace.browserPanes.count == 1)
        _ = try test.process.runCommand(["kill", first.uuidString.lowercased()])
        #expect(await waitUntil { workspace.layout.rows.isEmpty && workspace.browserPanes.isEmpty && workspace.shown == .nothing })
    }
}
