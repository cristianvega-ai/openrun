import AppKit
import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionWindow

@Suite(.isolatedThread) struct SessionListTests {
    @Test func theListNamesRunningSessionsAndCanBeEmpty() async throws {
        try await RunningSessionProcess.run { process in
            let location = try SocketLocation(path: process.socketPath)
            #expect(try await SessionList.summaries(at: location).isEmpty)
            let identifier = try process.createSession(program: ["/bin/sleep", "60"])
            let sessions = try await SessionList.summaries(at: location)
            #expect(sessions.count == 1 && sessions.first?.identifierText == identifier)
        }
    }

    @Test func aMissingSessionProcessIsAnErrorInsteadOfAnEmptyList() async throws {
        let directory = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = try SocketLocation(path: directory.appendingPathComponent("missing.socket").path)
        await #expect(throws: SessionConnectionError.noSessionProcess(socketPath: location.path)) { try await SessionList.summaries(at: location) }
    }

    @MainActor @Test func theListDoesNotWaitForTheSocketOnTheMainThread() async throws {
        let location = try SocketLocation(path: "/tmp/openrun-list-test.socket")
        let result = try await SessionList.summaries(at: location) { _ in
            #expect(!Thread.isMainThread)
            return []
        }
        #expect(result.isEmpty)
    }


    @MainActor @Test func theUserCanChooseOrCancelAndAnEmptyListIsExplained() async {
        _ = NSApplication.shared
        let first = SessionSummary(identifier: UUID(), folder: "/one", command: ["/bin/sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date())
        let second = SessionSummary(identifier: UUID(), folder: "/two", command: ["/bin/sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date())
        let selected = await SessionListPanel.choose([first, second], in: nil) { alert, _ in
            let choices = alert.accessoryView as? NSPopUpButton
            #expect(choices?.itemTitles == ["/one — \(first.identifierText)", "/two — \(second.identifierText)"])
            choices?.selectItem(at: 1)
            return .alertFirstButtonReturn
        }
        #expect(selected == second.identifier)
        let canceled = await SessionListPanel.choose([first], in: nil) { _, _ in .alertSecondButtonReturn }
        #expect(canceled == nil)
        let empty = await SessionListPanel.choose([], in: nil) { alert, _ in
            #expect(alert.messageText == "No running sessions")
            return .alertFirstButtonReturn
        }
        #expect(empty == nil)
    }

}
