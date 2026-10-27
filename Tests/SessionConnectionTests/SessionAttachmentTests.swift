import Foundation
import SessionProtocol
import Testing
@testable import SessionConnection

@Suite struct SessionAttachmentTests {
    private static let size = SessionSize(columns: 80, rows: 24)
    private static let summary = SessionSummary(identifier: UUID(), folder: "/", command: ["sh"], size: size, createdAt: Date(timeIntervalSince1970: 0))

    /// Attaches to a stand-in session process. It answers `answers` only to
    /// the attach message that a client of the tool sends, and then runs `then`.
    private static func attach(
        answering answers: [ServerMessage],
        then: @escaping @Sendable (MessageConnection) throws -> Void = { _ in }
    ) throws -> SessionAttachment {
        let client = try SessionClient.standIn { session in
            let expected = ClientMessage.attach(identifier: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: nil)
            guard try session.receive(ClientMessage.self) == expected else { return }
            for answer in answers { try session.send(answer) }
            try then(session)
        }
        return try client.attach(to: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: false)
    }

    /// Every event, up to the last one.
    private static func events(of attachment: SessionAttachment) async -> [SessionAttachmentEvent] {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionAttachmentEvent.self)
        attachment.startReceiving { event in
            continuation.yield(event)
            switch event {
            case .exited, .closed, .failed: continuation.finish()
            case .output, .sizeChanged: break
            }
        }
        return await stream.reduce(into: []) { $0.append($1) }
    }

    @Test func theEventsComeInTheOrderOfTheSessionProcessAndNothingFollowsTheExit() async throws {
        let attachment = try Self.attach(answering: [
            .attached(Self.summary), .snapshot(Data()), .output(Data("a".utf8)), .sizeChanged(SessionSize(columns: 100, rows: 30)),
            .output(Data("b".utf8)), .exited(.exited(status: 3)), .output(Data("after the exit".utf8)),
        ])
        #expect(await Self.events(of: attachment) == [
            .output(Data("a".utf8)), .sizeChanged(SessionSize(columns: 100, rows: 30)), .output(Data("b".utf8)), .exited(.exited(status: 3)),
        ])
    }

    /// The output goes on after a message that has no place there, and a
    /// connection that closes ends the events.
    @Test func aMessageThatDoesNotBelongAfterTheSnapshotIsIgnored() async throws {
        let attachment = try Self.attach(answering: [
            .attached(Self.summary), .snapshot(Data()), .output(Data("a".utf8)), .attached(Self.summary), .acknowledged, .output(Data("b".utf8)),
        ])
        #expect(await Self.events(of: attachment) == [.output(Data("a".utf8)), .output(Data("b".utf8)), .closed])
    }

    @Test func keysSizesAndTheDetachReachTheSessionProcessInOrder() async throws {
        let (received, receiving) = AsyncStream.makeStream(of: ClientMessage.self)
        let attachment = try Self.attach(answering: [.attached(Self.summary), .snapshot(Data())]) { session in
            while let message = try session.receive(ClientMessage.self) {
                receiving.yield(message)
                if message == .detach { break }
            }
            receiving.finish()
        }
        try attachment.send(input: Data("keys".utf8))
        try attachment.send(size: SessionSize(columns: 100, rows: 30))
        try attachment.detach()
        #expect(await received.reduce(into: []) { $0.append($1) } == [.input(Data("keys".utf8)), .resize(SessionSize(columns: 100, rows: 30)), .detach])
    }

    /// A shutdown wakes the receiving thread while it waits for a frame.
    @Test func aShutdownEndsTheEventsWithClosed() async throws {
        let attachment = try Self.attach(answering: [.attached(Self.summary), .snapshot(Data())]) { session in
            _ = try session.receive(ClientMessage.self)
        }
        async let events = Self.events(of: attachment)
        try await Task.sleep(for: .milliseconds(50))
        attachment.shutdown()
        #expect(await events == [.closed])
    }

    @Test func aFrameThatCannotBeReadEndsTheEventsWithFailed() async throws {
        let attachment = try Self.attach(answering: [.attached(Self.summary), .snapshot(Data())]) { session in
            try session.send(ClientMessage.input(Data("a client frame".utf8)))
        }
        #expect(await Self.events(of: attachment) == [.failed(.protocolFailure(.unexpectedMessage(description: "a client frame arrived at the client")))])
    }

    @Test func theSnapshotFollowsAttached() throws {
        let snapshot = Data("snapshot".utf8)
        #expect(try Self.attach(answering: [.attached(Self.summary), .snapshot(snapshot)]).snapshot == snapshot)
    }

    @Test func aFailureInPlaceOfAttachedIsRequestFailed() {
        let failure = SessionFailure(reason: .invalidRequest, message: "The screen of the session does not fit in one frame.")
        #expect(throws: SessionConnectionError.requestFailed(failure)) { try Self.attach(answering: [.failure(failure)]) }
    }

    @Test func outputBeforeTheSnapshotIsAnUnexpectedAnswer() {
        let error = #expect(throws: SessionConnectionError.self) {
            try Self.attach(answering: [.attached(Self.summary), .output(Data("early".utf8))])
        }
        #expect(error == .unexpectedAttachAnswer)
        #expect(error?.description == "The session process answered the attach request in an unexpected way.")
    }

    @Test func attachedTwiceAndNoSnapshotIsAMissingSnapshot() {
        let error = #expect(throws: SessionConnectionError.self) { try Self.attach(answering: [.attached(Self.summary), .attached(Self.summary)]) }
        #expect(error == .missingSnapshot)
        #expect(error?.description == "The session process sent no snapshot.")
    }
}
