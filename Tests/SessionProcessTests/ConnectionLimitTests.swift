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

/// Whether the session process has closed its side of this socket. The
/// socket may still hold bytes that the test never read.
private func isClosedBySessionProcess(_ descriptor: Int32) -> Bool {
    var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    return poll(&entry, 1, 0) > 0 && entry.revents & Int16(POLLHUP) != 0
}

private func writeAll(_ bytes: [UInt8], to descriptor: Int32) -> Bool {
    bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) == $0.count }
}

/// Receives one message, or `nil` when the connection closes or the time
/// limit passes. A test that waits too long fails instead of hanging.
private func receiveMessage(_ connection: MessageConnection, within limit: TimeInterval) throws -> ServerMessage? {
    let watchdog = DispatchWorkItem { connection.shutdown() }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    return try connection.receive(ServerMessage.self)
}

/// A greeted connection on a socket whose descriptor the test keeps.
private func greetedConnection(to path: String) throws -> (connection: MessageConnection, descriptor: Int32) {
    let descriptor = try connectedSocket(to: path)
    let connection = MessageConnection(descriptor: descriptor)
    try connection.greetSessionProcess()
    return (connection, descriptor)
}
extension SessionProcessIntegration {
    /// Each client costs a bounded amount: a thread, a descriptor, and memory
    /// for what it sends and receives. Deadlines end the clients that stop
    /// halfway, and a limit refuses clients past 64.
    @Suite struct ConnectionLimitTests {
        /// Closing a client that stopped reading waited for a write
        /// that never finished, so its descriptor and thread stayed for good.
        @Test func stalledClientsAreClosedSoonAfterTheirProgramEnds() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let descriptorsBefore = try #require(process.descriptorCount)
                let threadsBefore = try #require(process.threadCount)
                // One MiB of output is far below the 8 MiB limit, and far
                // more than the socket holds.
                let script = "while [ ! -e '\(goFile.path)' ]; do sleep 0.05; done; dd if=/dev/zero bs=65536 count=16 2>/dev/null; exit 7"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])

                var clients: [(connection: MessageConnection, descriptor: Int32)] = []
                for _ in 0..<6 {
                    let client = try greetedConnection(to: process.socketPath)
                    try client.connection.send(ClientMessage.attach(identifier: UUID(uuidString: identifier)!, size: SessionSize(columns: 80, rows: 24)))
                    guard case .attached = try receiveMessage(client.connection, within: 30),
                          case .snapshot = try receiveMessage(client.connection, within: 30) else {
                        Issue.record("The attach was not answered.")
                        return
                    }
                    clients.append(client)
                }
                defer { clients.forEach { $0.connection.shutdown() } }

                // The clients now read nothing more.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                #expect(await eventually { ((try? process.listedIdentifiers()) ?? [identifier]).isEmpty })
                let programEnded = ContinuousClock.now
                let closed = await eventually(timeout: .seconds(8)) { clients.allSatisfy { isClosedBySessionProcess($0.descriptor) } }
                print("stalled-clients: closed \(closed) \(ContinuousClock.now - programEnded) after the program ended")
                #expect(closed, "the session process kept stalled clients open after their program ended")

                // The system ends an idle worker thread of a dispatch queue about
                // five seconds after its last work, such as a stuck write.
                var descriptorsAfter = Int.max
                var threadsAfter = Int.max
                let released = await eventually(timeout: .seconds(15)) {
                    descriptorsAfter = process.descriptorCount ?? Int.max
                    threadsAfter = process.threadCount ?? Int.max
                    return descriptorsAfter <= descriptorsBefore && threadsAfter <= threadsBefore + 2
                }
                #expect(released, "descriptors \(descriptorsBefore) then \(descriptorsAfter); threads \(threadsBefore) then \(threadsAfter)")
            }
        }

        /// Nothing ended a client that stopped halfway, and a frame
        /// header made the session process allocate the whole announced body.
        @Test func slowAndSilentConnectionsAreEndedOnTimeAndHoldLittleMemory() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 30000; sleep 600"])
                #expect(await process.waitForScreen(of: identifier, containing: "30000"))
                let footprintBefore = try #require(process.memoryFootprint)
                let threadsBefore = try #require(process.threadCount)
                let descriptorsBefore = try #require(process.descriptorCount)
                let start = ContinuousClock.now

                // These never send their hello.
                let silent = try (0..<6).map { _ in try connectedSocket(to: process.socketPath) }
                // These send two bytes of a hello and stop.
                let partial = try (0..<6).map { _ in
                    let descriptor = try connectedSocket(to: process.socketPath)
                    #expect(writeAll([0, 0], to: descriptor))
                    return descriptor
                }
                defer { (silent + partial).forEach { close($0) } }
                // These say hello, announce a frame of 64 MiB, send 100 bytes
                // of it, and stop.
                let announced = try (0..<4).map { _ in
                    let client = try greetedConnection(to: process.socketPath)
                    #expect(writeAll([0x04, 0x00, 0x00, 0x01, 3] + [UInt8](repeating: 0x61, count: 100), to: client.descriptor))
                    return client
                }
                // This one asks for the screen and its scrollback, and never
                // reads the answer, which is larger than the socket holds.
                let reader = try greetedConnection(to: process.socketPath)
                try reader.connection.send(ClientMessage.readScreen(identifier: UUID(uuidString: identifier)!, includeScrollback: true))
                defer { (announced + [reader]).forEach { $0.connection.shutdown() } }

                try await Task.sleep(for: .seconds(2))
                let footprint = try #require(process.memoryFootprint)
                let threads = try #require(process.threadCount)
                print("slow-connections: footprint \(footprintBefore) then \(footprint); threads \(threadsBefore) then \(threads)")
                #expect(footprint - footprintBefore < 32 * 1024 * 1024, "footprint grew from \(footprintBefore) to \(footprint) bytes")
                #expect(threads <= threadsBefore + 17 + 8, "threads went from \(threadsBefore) to \(threads)")
                #expect(!(silent + partial).contains(where: isClosedBySessionProcess), "a connection was closed before its hello deadline")
                // Other clients are served meanwhile.
                #expect(try process.runCommand(["list"]).status == 0)

                // Hello must arrive within 5 seconds.
                let helloEnded = await eventually(timeout: start + .seconds(8) - ContinuousClock.now) {
                    (silent + partial).allSatisfy(isClosedBySessionProcess)
                }
                #expect(helloEnded, "connections without a hello were still open \(ContinuousClock.now - start) after they connected")
                // A write that makes no progress for 10 seconds ends the client.
                let writeEnded = await eventually(timeout: start + .seconds(15) - ContinuousClock.now) { isClosedBySessionProcess(reader.descriptor) }
                #expect(writeEnded, "a client that read nothing was still open \(ContinuousClock.now - start) after it asked")
                #expect(!announced.contains { isClosedBySessionProcess($0.descriptor) }, "a frame was ended before its 30 second stall limit")
                // A frame that stalls for 30 seconds ends the client.
                let frameEnded = await eventually(timeout: start + .seconds(36) - ContinuousClock.now) {
                    announced.allSatisfy { isClosedBySessionProcess($0.descriptor) }
                }
                #expect(frameEnded, "stalled frames were still open \(ContinuousClock.now - start) after they started")

                var descriptorsAfter = Int.max
                var threadsAfter = Int.max
                let released = await eventually(timeout: .seconds(15)) {
                    descriptorsAfter = process.descriptorCount ?? Int.max
                    threadsAfter = process.threadCount ?? Int.max
                    return descriptorsAfter <= descriptorsBefore + 1 && threadsAfter <= threadsBefore + 4
                }
                #expect(released, "descriptors \(descriptorsBefore) then \(descriptorsAfter); threads \(threadsBefore) then \(threadsAfter)")
            }
        }

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
