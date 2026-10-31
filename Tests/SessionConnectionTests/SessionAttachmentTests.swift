import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

@Suite struct SessionAttachmentTests {
    private static let size = SessionSize(columns: 80, rows: 24)
    private static let summary = SessionSummary(identifier: UUID(), folder: "/", command: ["sh"], size: size, createdAt: Date(timeIntervalSince1970: 0))

    private enum EarlierClientMessage: Codable, Equatable {
        case attach(identifier: UUID, size: SessionSize, relaysRawOutput: Bool?, receivesSizeChanges: Bool?)
    }

    private static func attachFrame(throughClient: Bool, waitsForOutputRoom: Bool?) throws -> MessageFrame {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        let received = Mutex<MessageFrame?>(nil)
        Thread {
            defer { sessionSide.shutdown() }
            do {
                if throughClient { try sessionSide.greetClient() }
                guard let frame = try sessionSide.receive(MessageFrame.self) else { return }
                received.withLock { $0 = frame }
                try sessionSide.send(ServerMessage.attached(summary))
                try sessionSide.send(ServerMessage.snapshot(Data()))
            } catch {}
        }.start()
        let attachment: SessionAttachment
        if throughClient {
            let client = try SessionClient(greeting: clientSide)
            if let waitsForOutputRoom {
                attachment = try client.attach(to: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: false, waitsForOutputRoom: waitsForOutputRoom)
            } else {
                attachment = try client.attach(to: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: false)
            }
        } else if let waitsForOutputRoom {
            attachment = try SessionAttachment.attach(on: clientSide, to: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: false, waitsForOutputRoom: waitsForOutputRoom)
        } else {
            attachment = try SessionAttachment.attach(on: clientSide, to: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: false)
        }
        defer { attachment.shutdown() }
        return try #require(received.withLock { $0 })
    }

    @Test func outputRoomIsOptInAndKeepsTheEarlierWireMessageByDefault() throws {
        let earlier = EarlierClientMessage.attach(identifier: Self.summary.identifier, size: Self.size, relaysRawOutput: true, receivesSizeChanges: nil)
        let earlierObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(earlier)) as? NSObject)
        for throughClient in [false, true] {
            for choice in [nil, false, true] as [Bool?] {
                let frame = try Self.attachFrame(throughClient: throughClient, waitsForOutputRoom: choice)
                #expect(frame.kind == .control)
                #expect(try JSONDecoder().decode(EarlierClientMessage.self, from: frame.payload) == earlier)
                let object = try #require(JSONSerialization.jsonObject(with: frame.payload) as? NSObject)
                let fields = try #require((object as? [String: Any])?["attach"] as? [String: Any])
                if choice == true {
                    #expect(fields["waitsForOutputRoom"] as? Bool == true)
                } else {
                    #expect(object == earlierObject)
                    #expect(fields["waitsForOutputRoom"] == nil)
                }
            }
        }
    }

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
            .attached(Self.summary), .snapshot(Data()), .output(Data("a".utf8)), .attached(Self.summary), .acknowledged, .failure(SessionFailure(reason: .invalidRequest, message: "ignored")), .output(Data("b".utf8)),
        ])
        #expect(await Self.events(of: attachment) == [.output(Data("a".utf8)), .output(Data("b".utf8)), .closed])
    }

    @Test func aFailureAfterAConfirmedResizeEndsTheEvents() async throws {
        let failure = SessionFailure(reason: .invalidRequest, message: "The size is invalid.")
        let attachment = try Self.attach(answering: [.attached(Self.summary), .snapshot(Data())]) { session in
            _ = try session.receive(ClientMessage.self)
            try session.send(ServerMessage.failure(failure))
        }
        try attachment.send(size: Self.size, requestsConfirmation: true)
        #expect(await Self.events(of: attachment) == [.failed(.requestFailed(failure))])
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
        try attachment.send(size: Self.size, requestsConfirmation: true)
        try attachment.detach()
        #expect(await received.reduce(into: []) { $0.append($1) } == [.input(Data("keys".utf8)), .resize(SessionSize(columns: 100, rows: 30)), .resize(Self.size, requestsConfirmation: true), .detach])
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
