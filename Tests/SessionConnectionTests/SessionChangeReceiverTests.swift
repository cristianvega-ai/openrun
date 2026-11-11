import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

@Suite struct SessionChangeReceiverTests {
    private static let summary = SessionSummary(identifier: UUID(), folder: "/", command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 0))

    private static func events(of receiver: SessionChangeReceiver, count: Int) async throws -> [SessionChangeReceiver.Event] {
        let events = Mutex<[SessionChangeReceiver.Event]>([])
        receiver.startReceiving { event in events.withLock { $0.append(event) } }
        let deadline = ContinuousClock.now + .seconds(10)
        while events.withLock({ $0.count }) < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return events.withLock { $0 }
    }

    /// The list comes first, then each change and end, and last the close.
    @Test func handsOnTheListTheChangesAndTheClose() async throws {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        defer { clientSide.shutdown(); sessionSide.shutdown() }
        var changed = Self.summary
        changed.isInProgress = true
        Thread {
            defer { sessionSide.shutdown() }
            guard (try? sessionSide.receive(ClientMessage.self)) == .receiveSessionChanges else { return }
            try? sessionSide.send(ServerMessage.sessionList([Self.summary]))
            try? sessionSide.send(ServerMessage.sessionChanged(changed))
            try? sessionSide.send(ServerMessage.sessionEnded(identifier: changed.identifier))
        }.start()
        let receiver = try SessionChangeReceiver.open(on: clientSide)
        #expect(try await Self.events(of: receiver, count: 4) == [
            .sessions([Self.summary]), .sessionChanged(changed), .sessionEnded(changed.identifier), .closed,
        ])
    }

    @Test func handsOnTheProjectsAndTheSettings() async throws {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        defer { clientSide.shutdown(); sessionSide.shutdown() }
        let projects = [ProjectSummary(identifier: UUID(), name: "App", folder: "/work/app")]
        let settings = [SettingSummary(name: "session-limit", text: "100", isProtected: true)]
        Thread {
            defer { sessionSide.shutdown() }
            _ = try? sessionSide.receive(ClientMessage.self)
            try? sessionSide.send(ServerMessage.sessionList([]))
            try? sessionSide.send(ServerMessage.projectList(projects))
            try? sessionSide.send(ServerMessage.settingList(settings))
        }.start()
        let receiver = try SessionChangeReceiver.open(on: clientSide)
        #expect(try await Self.events(of: receiver, count: 4) == [.sessions([]), .projects(projects), .settings(settings), .closed])
    }

    @Test func aRefusalEndsTheRequest() throws {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        defer { clientSide.shutdown(); sessionSide.shutdown() }
        let failure = SessionFailure(reason: .invalidRequest, message: "This connection is attached.")
        Thread {
            _ = try? sessionSide.receive(ClientMessage.self)
            try? sessionSide.send(ServerMessage.failure(failure))
        }.start()
        #expect(throws: SessionConnectionError.requestFailed(failure)) { try SessionChangeReceiver.open(on: clientSide) }
    }

    @Test func aBrokenFrameEndsWithAFailure() async throws {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        defer { clientSide.shutdown(); sessionSide.shutdown() }
        Thread {
            _ = try? sessionSide.receive(ClientMessage.self)
            try? sessionSide.send(ServerMessage.sessionList([]))
            try? sessionSide.send(MessageFrame(kind: .control, payload: Data("not json".utf8)))
        }.start()
        let events = try await Self.events(of: try SessionChangeReceiver.open(on: clientSide), count: 2)
        #expect(events.first == .sessions([]))
        guard case .failed(.protocolFailure) = events.last else {
            Issue.record("The receiver ended with \(String(describing: events.last))")
            return
        }
    }
}
