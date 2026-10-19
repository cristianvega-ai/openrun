import Darwin
import Foundation
@testable import SessionProcess
import SessionProcessHarness
@testable import SessionProtocol
import Testing

extension SessionProcessIntegration {
    @Suite struct SocketSecurityTests {

        // MARK: - The user at the other end
        //
        // This Mac has one user account, and a test cannot start a program as
        // another user. So these tests make each side expect another user
        // than the one it meets, through a parameter that only tests set.

        @Test func thePeerOfASocketIsTheUserOfThisProcess() throws {
            let (one, other) = try MessageConnection.makePair()
            #expect(throws: Never.self) { try one.requirePeer() }
            #expect(throws: Never.self) { try other.requirePeer(PeerIdentity(userIdentifier: geteuid())) }
        }

        /// The session process closes a connection of another user before it
        /// sends a byte, and never serves it.
        @Test func theSessionProcessRefusesAClientOfAnotherUser() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let anotherUser = PeerIdentity(userIdentifier: geteuid() &+ 1)

            for (allowed, served) in [(anotherUser, false), (PeerIdentity.currentUser, true)] {
                let location = try SocketLocation(path: folder.appendingPathComponent(served ? "served" : "refused").path)
                let listener = try SocketListener(location: location, allowedPeer: allowed)
                let connections = listener.connections
                let counting = Task {
                    var count = 0
                    for await connection in connections {
                        count += 1
                        connection.shutdown()
                    }
                    return count
                }
                let client = try MessageConnection.connect(to: location)
                // A refused client sees the connection end with no byte. A
                // served one waits for an answer that this test never gives.
                let answer = Result { try client.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .milliseconds(served ? 300 : 5000))) }
                client.shutdown()
                listener.close()
                let count = await counting.value
                if served {
                    #expect(count == 1)
                } else {
                    #expect(count == 0)
                    #expect(try answer.get() == nil)
                }
            }
        }

        // MARK: - Connections that wait for the server

        /// The listener kept every connection it accepted
        /// until the server took it, with no limit, outside the client limit
        /// and before the hello deadline. Now a fixed number wait, and the
        /// listener closes the rest at once.
        @Test func connectionsPastTheLimitThatWaitForTheServerAreClosedAtOnce() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let location = try SocketLocation(path: folder.appendingPathComponent("socket").path)
            let listener = try SocketListener(location: location)
            let limit = SocketListener.waitingConnectionLimit
            let clientCount = limit + 24
            // Nothing takes the connections, as when the server is busy.
            var clients: [MessageConnection] = []
            defer { clients.forEach { $0.shutdown() } }
            for _ in 0..<clientCount {
                clients.append(try MessageConnection.connect(to: location))
            }

            let closed = await eventually(timeout: .seconds(5)) {
                clients.filter(\.peerHasClosed).count >= clientCount - limit
            }
            let closedCount = clients.filter(\.peerHasClosed).count
            #expect(closed && closedCount == clientCount - limit, "\(closedCount) of \(clientCount) connections were closed")
            let waitingClosed = clients.prefix(limit).filter(\.peerHasClosed).count
            #expect(waitingClosed == 0, "\(waitingClosed) of the connections that wait were closed")

            listener.close()
            var waited = 0
            for await connection in listener.connections {
                waited += 1
                connection.shutdown()
            }
            #expect(waited == limit)
        }
    }
}
