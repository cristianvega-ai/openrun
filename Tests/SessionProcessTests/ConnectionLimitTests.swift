import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

private enum SocketError: Error {
    case connectFailed(code: Int32)
}

/// A Unix socket connected to the session process. The test keeps the
/// descriptor, so it can write bytes by hand and see when the session process
/// closes its side.
private func connectedSocket(to path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    // Set before connecting: once the other side has closed, the system
    // refuses the option, and a write would end the test with SIGPIPE.
    var enabled: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8.prefix($0.count - 1)) }
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
    }
    guard descriptor >= 0, result == 0 else {
        let code = errno
        if descriptor >= 0 { close(descriptor) }
        throw SocketError.connectFailed(code: code)
    }
    return descriptor
}
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

        /// The listener could spin when the process runs out of
        /// descriptors. On macOS a failed accept drops the waiting connection
        /// instead, so the old listener did not spin: it dropped every waiting
        /// client at once. The listener now waits a little after a failed
        /// accept, so clients that wait during a short shortage are served.
        @Test func runningOutOfDescriptorsNeitherSpinsNorDropsEveryWaitingClient() async throws {
            let process = try RunningSessionProcess(descriptorLimit: 40)
            defer { process.stop() }
            let before = try #require(process.processorTime)
            // These use up the descriptors of the process.
            let first = try (0..<36).map { _ in try connectedSocket(to: process.socketPath) }
            // These wait in the queue of the listening socket.
            let waiting = try (0..<14).map { _ in MessageConnection(descriptor: try connectedSocket(to: process.socketPath)) }
            defer {
                first.forEach { close($0) }
                waiting.forEach { $0.shutdown() }
            }

            try await Task.sleep(for: .seconds(1))
            let after = try #require(process.processorTime)
            print("descriptor-limit: processor time \(after - before) in 1 second; descriptors \(process.descriptorCount.map(String.init) ?? "unknown")")
            #expect(after - before < .milliseconds(300), "the process used \(after - before) of processor time in 1 second")

            // The first clients leave and free descriptors. The waiting ones
            // are then accepted and served.
            first.forEach { shutdown($0, SHUT_RDWR) }
            let served = await Task.detached { () -> Int in
                var served = 0
                let deadline = Date().addingTimeInterval(4)
                for connection in waiting {
                    let watchdog = DispatchWorkItem { connection.shutdown() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + max(0.05, deadline.timeIntervalSinceNow), execute: watchdog)
                    if (try? connection.greetSessionProcess()) != nil { served += 1 }
                    watchdog.cancel()
                }
                return served
            }.value
            print("descriptor-limit: \(served) of \(waiting.count) waiting clients were served")
            #expect(served >= 10, "\(served) of the \(waiting.count) waiting clients were served")
        }
    }
}
