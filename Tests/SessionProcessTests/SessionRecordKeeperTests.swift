import DataStorage
import Foundation
import SessionProcessHarness
import SessionProtocol
import SessionRecords
import Testing
@testable import SessionProcess

@Suite struct SessionRecordKeeperTests {
    private func summary(_ folder: String = "/work/app", at seconds: Double = 0) -> SessionSummary {
        SessionSummary(identifier: UUID(), folder: folder, command: ["/bin/zsh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func theFileFollowsTheSessionsThatRun() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let keeper = SessionRecordKeeper(store: SessionRecordStore(dataFolder: DataFolder(path: folder.path)), saveDelay: .milliseconds(10))
        #expect(keeper.load().isEmpty)
        var (first, second) = (summary(at: 1), summary("/work/site", at: 2))
        for session in [second, first] { await keeper.keep(session) }
        #expect(await eventually { keeper.load().map(\.identifier) == [first.identifier, second.identifier] })
        // The record follows the folder, the name and the size of its session.
        (first.currentFolder, first.name, first.size) = ("/work/app/Sources", "Build", SessionSize(columns: 120, rows: 40))
        await keeper.keep(first)
        let moved = SessionRecord(identifier: first.identifier, folder: "/work/app/Sources", name: "Build", columns: 120, rows: 40, createdAt: first.createdAt)
        #expect(await eventually { keeper.load().first == moved } && keeper.load().count == 2)
    }

    private func makeKeeper(endGrace: Duration) throws -> (SessionRecordKeeper, URL) {
        let folder = try RunningSessionProcess.makeDirectory()
        let store = SessionRecordStore(dataFolder: DataFolder(path: folder.path))
        return (SessionRecordKeeper(store: store, saveDelay: .milliseconds(10), endGrace: endGrace), folder)
    }

    @Test func aSessionThatEndedAndTheTerminalOfAThreadDoNotComeBack() async throws {
        let (keeper, folder) = try makeKeeper(endGrace: .milliseconds(20))
        defer { try? FileManager.default.removeItem(at: folder) }
        let (first, second, terminal) = (summary(at: 1), summary(at: 2), summary(at: 3))
        for session in [first, second, terminal] { await keeper.keep(session) }
        // The thread keeps the conversation of its terminal.
        await keeper.exclude(terminal.identifier)
        await keeper.keep(terminal)
        await keeper.forget(second.identifier)
        #expect(await eventually { keeper.load().map(\.identifier) == [first.identifier] })
    }

    @Test func theSessionsThatRunAtAStopStayInTheFile() async throws {
        let (keeper, folder) = try makeKeeper(endGrace: .milliseconds(300))
        defer { try? FileManager.default.removeItem(at: folder) }
        let (first, second) = (summary(at: 1), summary(at: 2))
        for session in [first, second] { await keeper.keep(session) }
        // At a shutdown of the Mac, a program can end a moment before the session process stops.
        await keeper.forget(first.identifier)
        await keeper.stop()
        await keeper.forget(second.identifier)
        try await Task.sleep(for: .milliseconds(450))
        #expect(keeper.load().map(\.identifier) == [first.identifier, second.identifier])
    }
}
