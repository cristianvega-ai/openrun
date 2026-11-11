import AppKit
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionPane
@testable import TerminalView

/// A pane in a view of a plain window, as the main window holds it.
@MainActor @Suite(.serialized) struct SessionPaneControllerTests {
    @Test func theTitleIsTheFolderUntilTheProgramSetsOne() async throws {
        try await withSessionProcess { process, folder in
            let hosted = try await hostPane(in: process, folder: folder)
            defer { hosted.pane.close() }
            #expect(hosted.host.titles == [hosted.pane.title] && !hosted.pane.title.isEmpty)
            hosted.pane.terminalView(try #require(hosted.pane.terminalView), send: Array("printf '\\033]2;Pane title\\007'\r".utf8))
            await waitOnMainThread { hosted.pane.title == "Pane title" }
            #expect(hosted.host.titles.last == "Pane title")
        }
    }

    @Test func theTerminalTakesTheFocusOnlyWhenThePaneHadIt() async throws {
        try await withSessionProcess { process, folder in
            let focused = try await hostPane(in: process, folder: folder)
            defer { focused.pane.close() }
            #expect(focused.window.firstResponder === focused.pane.terminalView)
            let other = try await hostPane(in: process, folder: folder, focusesPane: false)
            defer { other.pane.close() }
            #expect(other.window.firstResponder is NSTextView)
        }
    }

    @Test func theEndOfTheProgramReachesTheHostAndACloseKeepsTheSession() async throws {
        try await withSessionProcess { process, folder in
            let kept = try await hostPane(in: process, folder: folder)
            kept.pane.close()
            #expect(try process.listedIdentifiers() == [kept.identifier])
            let ending = try await hostPane(in: process, folder: folder)
            ending.pane.terminalView(try #require(ending.pane.terminalView), send: Array("exit\r".utf8))
            await waitOnMainThread { ending.host.ends == 1 }
            #expect(ending.host.ends == 1)
            ending.pane.close()
        }
    }
}
