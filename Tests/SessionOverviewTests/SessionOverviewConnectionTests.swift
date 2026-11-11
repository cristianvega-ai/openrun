import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionOverview

@MainActor @Suite(.serialized) struct SessionOverviewConnectionTests {
    @Test func theOverviewFollowsARealSessionProcess() async throws {
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let connection = SessionOverviewConnection(socket: try SocketLocation(path: process.socketPath))
        var previousCounts: [Int] = []
        connection.overviewChanged = { previousCounts.append($0.sessions.count) }
        #expect(!connection.hasSessionList && !connection.hasThreadList && !connection.hasFirstLists)
        connection.start()
        connection.start()
        let identifier = try process.createSession(program: ["/bin/sh"])
        #expect(await waitUntil { connection.overview.sessions.map(\.identifierText) == [identifier] })
        #expect(connection.status == .connected && connection.hasSessionList)
        #expect(await waitUntil { connection.hasThreadList && connection.hasFirstLists })
        #expect(connection.overview.settingText(named: "font-size") == "13")
        _ = try process.runCommand(["rename", identifier, "Build"])
        #expect(await waitUntil { connection.overview.sessions.first?.name == "Build" })
        _ = try process.runCommand(["project", "add", process.directory.path])
        #expect(await waitUntil { connection.overview.projects.count == 1 })
        _ = try process.runCommand(["kill", identifier])
        #expect(await waitUntil { connection.overview.sessions.isEmpty })
        #expect(previousCounts.first == 0 && previousCounts.last == 1)
    }

    @Test func aSocketWithNoSessionProcessGivesTheReason() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = SessionOverviewConnection(socket: try SocketLocation(path: folder.appendingPathComponent("socket").path))
        var statuses: [ConnectionStatus] = []
        connection.statusChanged = { statuses.append(connection.status) }
        connection.start()
        #expect(await waitUntil { statuses.count == 1 })
        guard case .disconnected(let reason) = connection.status else { Issue.record("\(connection.status)"); return }
        #expect(reason.contains("No session process answers"))
    }

    /// The sessions of a session process end with it. The next session
    /// process on the socket brings a new list.
    @Test func theConnectionComesBackAfterTheSessionProcessStartsAgain() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try RunningSessionProcess(directory: folder)
        let connection = SessionOverviewConnection(socket: try SocketLocation(path: first.socketPath))
        connection.firstRetryDelay = .milliseconds(20)
        connection.start()
        _ = try first.createSession(program: ["/bin/sh"])
        #expect(await waitUntil { connection.overview.sessions.count == 1 })
        first.stop()
        // A session process that stops ends its sessions and says so.
        #expect(await waitUntil { connection.status != .connected && connection.overview.sessions.isEmpty })
        let second = try RunningSessionProcess(directory: folder, logName: "log2")
        defer { second.stop() }
        _ = try second.createSession(program: ["/bin/sh"])
        #expect(await waitUntil { connection.status == .connected && connection.overview.sessions.count == 1 })
        connection.stop()
        _ = try second.createSession(program: ["/bin/sh"])
        try await Task.sleep(for: .milliseconds(300))
        #expect(connection.overview.sessions.count == 1)
    }
}
