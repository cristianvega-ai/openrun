import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// Each client costs a bounded amount: a thread, a descriptor, and memory
    /// for what it sends and receives. Deadlines end the clients that stop
    /// halfway, and a limit refuses clients past 64.
    @Suite struct ConnectionLimitTests {

        /// Every connection got a thread, without a limit.
        @Test func clientsPastTheLimitAreRefusedAndTheThreadsStayBounded() async throws {
            try await RunningSessionProcess.run { process in
                let threadsBefore = try #require(process.threadCount)
                var connections: [MessageConnection] = []
                defer { connections.forEach { $0.shutdown() } }
                for _ in 0..<64 {
                    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                    try connection.greetSessionProcess()
                    connections.append(connection)
                }
                var answers: [String] = []
                for _ in 0..<36 {
                    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                    do {
                        try connection.greetSessionProcess()
                        answers.append("accepted")
                        connections.append(connection)
                    } catch {
                        answers.append("\(error)")
                    }
                }
                let threads = try #require(process.threadCount)
                print("client-limit: threads \(threadsBefore) then \(threads); answers past the limit: \(Set(answers))")
                #expect(answers.allSatisfy { $0.contains("64 clients") }, "answers past the limit: \(Set(answers))")
                #expect(threads <= threadsBefore + 64 + 8, "threads went from \(threadsBefore) to \(threads)")

                // A client that leaves makes room for another.
                connections.removeFirst().shutdown()
                #expect(await eventually(timeout: .seconds(5)) { (try? process.runCommand(["list"]).status) == 0 })
            }
        }
    }
}
