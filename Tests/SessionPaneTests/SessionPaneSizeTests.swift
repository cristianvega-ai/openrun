import AppKit
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionPane
@testable import TerminalView

/// The size rules of a pane that a plain view holds (decisions of 2026-10-27 and 2026-11-08).
@MainActor @Suite(.serialized) struct SessionPaneSizeTests {
    @Test func activationTakesBackTheGridOfThePane() async throws {
        try await withSessionProcess { process, folder in
            let hosted = try await hostPane(in: process, folder: folder)
            defer { hosted.pane.close() }
            let view = try #require(hosted.pane.terminalView), own = try #require(view.visibleGridSize)
            let other = try SessionStart.runningSession(try #require(UUID(uuidString: hosted.identifier))).attach(
                at: try SocketLocation(path: process.socketPath), size: SessionSize(columns: own.columns + 10, rows: own.rows + 5))
            defer { other.attachment.shutdown() }
            await waitOnMainThread { view.gridSize != own }
            #expect(view.gridSize == TerminalSize(columns: own.columns + 10, rows: own.rows + 5))
            hosted.pane.activate()
            await waitOnMainThread { view.gridSize == own }
            #expect(view.gridSize == own)
        }
    }

    @Test func aLargerTextGivesALargerMinimumSize() async throws {
        try await withSessionProcess { process, folder in
            let hosted = try await hostPane(in: process, folder: folder)
            defer { hosted.pane.close() }
            let (before, reports) = (hosted.pane.minimumSize, hosted.host.minimumSizeReports)
            try #require(hosted.pane.terminalView).increaseFontSize(nil)
            #expect(hosted.host.minimumSizeReports == reports + 1)
            #expect(hosted.pane.minimumSize.width > before.width && hosted.pane.minimumSize.height > before.height)
        }
    }
}
