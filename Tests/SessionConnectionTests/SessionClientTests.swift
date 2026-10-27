import Darwin
import Foundation
import SessionProtocol
import Testing
@testable import SessionConnection

@Suite struct SessionClientTests {
    /// A socket path holds at most 103 bytes, and `TMPDIR` can be longer.
    private static func socketLocation(named name: String) throws -> SocketLocation {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let folder = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return try SocketLocation(path: (folder as NSString).appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).socket"))
    }

    @Test func aSocketThatDoesNotExistMeansNoSessionProcess() throws {
        let location = try Self.socketLocation(named: "absent")
        #expect(throws: SessionConnectionError.noSessionProcess(socketPath: location.path)) {
            try SessionClient(location: location)
        }
    }

    /// A session process that crashed leaves its socket file, and nothing
    /// accepts connections on it.
    @Test func aSocketThatNobodyListensOnMeansNoSessionProcess() throws {
        let location = try Self.socketLocation(named: "stale")
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { unlink(location.path) }
        try #require(location.withAddress { bind(descriptor, $0, $1) } == 0)
        close(descriptor)
        let error = #expect(throws: SessionConnectionError.self) { try SessionClient(location: location) }
        #expect(error == .noSessionProcess(socketPath: location.path))
        #expect(error?.description == "No session process answers on \(location.path).")
    }

    @Test func aSessionProcessOfAnotherVersionIsAProtocolFailure() throws {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        let theirs = MessageFrame.protocolVersion + 1
        try sessionSide.send(ServerMessage.hello(protocolVersion: theirs))
        let error = #expect(throws: SessionConnectionError.self) { try SessionClient(greeting: clientSide) }
        let protocolError = SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: theirs)
        #expect(error == .protocolFailure(protocolError))
        #expect(error?.description == protocolError.description)
    }

    @Test func aTypedIdentifierFindsItsSessionInTheList() throws {
        let summary = SessionSummary(identifier: UUID(), folder: "/work", command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 0))
        let client = try SessionClient.standIn { session in
            guard try session.receive(ClientMessage.self) == .listSessions else { return }
            try session.send(ServerMessage.sessionList([summary]))
        }
        #expect(try client.session(matching: String(summary.identifierText.prefix(4)).uppercased()) == summary)
    }

    @Test func aFailureAnswerIsRequestFailed() throws {
        let failure = SessionFailure(reason: .unknownSession, message: "No session has this identifier.")
        let client = try SessionClient.standIn { session in
            _ = try session.receive(ClientMessage.self)
            try session.send(ServerMessage.failure(failure))
        }
        let error = #expect(throws: SessionConnectionError.self) { try client.request(.killSession(identifier: UUID())) }
        #expect(error == .requestFailed(failure))
        #expect(error?.description == failure.message)
    }

    @Test func aConnectionThatClosesBeforeTheAnswerIsConnectionClosed() throws {
        let client = try SessionClient.standIn { session in
            _ = try session.receive(ClientMessage.self)
        }
        let error = #expect(throws: SessionConnectionError.self) { try client.summaries() }
        #expect(error == .connectionClosed)
        #expect(error?.description == "The session process closed the connection.")
    }

    @Test func anAnswerThatDoesNotFitTheRequestIsUnexpected() throws {
        let client = try SessionClient.standIn { session in
            _ = try session.receive(ClientMessage.self)
            try session.send(ServerMessage.acknowledged)
        }
        let error = #expect(throws: SessionConnectionError.self) { try client.summaries() }
        #expect(error == .unexpectedAnswer(request: "list"))
        #expect(error?.description == "The session process gave an unexpected answer to the list request.")
    }
}

extension SessionClient {
    /// A client of a stand-in session process on a socket pair. The stand-in
    /// greets the client, runs `answer` on a thread of its own, and closes.
    static func standIn(answering answer: @escaping @Sendable (MessageConnection) throws -> Void) throws -> SessionClient {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        Thread {
            defer { sessionSide.shutdown() }
            guard (try? sessionSide.greetClient()) != nil else { return }
            try? answer(sessionSide)
        }.start()
        return try SessionClient(greeting: clientSide)
    }
}
