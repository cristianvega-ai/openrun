import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    @Suite struct ResizeConfirmationTests {
        @Test func theProcessConfirmsChangesAndNoOpRequestsAndRefusesInvalidSizes() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try #require(UUID(uuidString: process.createSession(program: ["/bin/sleep", "60"])))
                let client = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                let watchdog = DispatchWorkItem { client.shutdown() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
                defer { watchdog.cancel(); client.shutdown() }
                #expect(try client.greetSessionProcess().orderedResizeConfirmation)
                let initial = SessionSize(columns: 80, rows: 24)
                try client.send(ClientMessage.attach(identifier: identifier, size: initial, receivesSizeChanges: true))
                guard case .attached = try client.receive(ServerMessage.self),
                      case .snapshot = try client.receive(ServerMessage.self) else {
                    Issue.record("The client did not receive its snapshot.")
                    return
                }
                let changed = SessionSize(columns: 100, rows: 30)
                try client.send(ClientMessage.resize(changed, requestsConfirmation: true))
                #expect(try client.receive(ServerMessage.self) == .sizeChanged(changed))
                try client.send(ClientMessage.resize(changed, requestsConfirmation: true))
                #expect(try client.receive(ServerMessage.self) == .sizeChanged(changed))
                try client.send(ClientMessage.resize(SessionSize(columns: 0, rows: 30), requestsConfirmation: true))
                guard case .failure(let failure) = try client.receive(ServerMessage.self) else {
                    Issue.record("The client received no failure for an invalid size.")
                    return
                }
                #expect(failure.reason == .invalidRequest)
                #expect(try client.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(5))) == nil)
            }
        }
    }
}
