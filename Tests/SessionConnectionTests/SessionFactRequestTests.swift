import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

@Suite struct SessionFactRequestTests {
    @Test func eachRequestSendsItsMessageAndTakesTheAcknowledgement() throws {
        let identifier = UUID()
        let received = Mutex<[ClientMessage]>([])
        let client = try SessionClient.standIn { sessionSide in
            while let message = try sessionSide.receive(ClientMessage.self) {
                received.withLock { $0.append(message) }
                try sessionSide.send(ServerMessage.acknowledged)
            }
        }
        try client.rename(session: identifier, to: "Release")
        try client.rename(session: identifier, to: nil)
        try client.raiseAlert(session: identifier, text: "Done")
        try client.clearAlert(session: identifier)
        #expect(received.withLock { $0 } == [
            .renameSession(identifier: identifier, name: "Release"), .renameSession(identifier: identifier, name: nil),
            .raiseSessionAlert(identifier: identifier, text: "Done"), .clearSessionAlert(identifier: identifier),
        ])
    }

    @Test func aRefusalBecomesAnError() throws {
        let failure = SessionFailure(reason: .invalidRequest, message: "Only a program outside every session may rename it.")
        let client = try SessionClient.standIn { sessionSide in
            _ = try sessionSide.receive(ClientMessage.self)
            try sessionSide.send(ServerMessage.failure(failure))
        }
        #expect(throws: SessionConnectionError.requestFailed(failure)) { try client.rename(session: UUID(), to: "x") }
    }
}
