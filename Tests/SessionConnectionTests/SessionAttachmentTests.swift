import Foundation
import SessionProtocol
import Testing
@testable import SessionConnection

@Suite struct SessionAttachmentTests {
    private static let size = SessionSize(columns: 80, rows: 24)
    private static let summary = SessionSummary(identifier: UUID(), folder: "/", command: ["sh"], size: size, createdAt: Date(timeIntervalSince1970: 0))

    /// Attaches to a stand-in session process. It answers `answers` only to
    /// the attach message that a client of the tool sends.
    private static func attach(answering answers: [ServerMessage]) throws -> SessionAttachment {
        let client = try SessionClient.standIn { session in
            let expected = ClientMessage.attach(identifier: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: nil)
            guard try session.receive(ClientMessage.self) == expected else { return }
            for answer in answers { try session.send(answer) }
        }
        return try client.attach(to: summary.identifier, size: size, relaysRawOutput: true, receivesSizeChanges: false)
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
