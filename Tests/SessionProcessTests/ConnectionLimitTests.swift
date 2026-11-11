import Darwin
import Foundation
import PseudoTerminal
@testable import SessionProcess
import SessionProcessHarness
import SessionProtocol
import Synchronization
import TerminalEmulation
import Testing

enum SocketError: Error {
    case connectFailed(code: Int32)
}

/// A Unix socket connected to the session process. The test keeps the
/// descriptor, so it can write bytes by hand and see when the session process
/// closes its side.
func connectedSocket(to path: String) throws -> Int32 {
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

/// The process and the count of chunks that a program wrote to its progress
/// file. The program replaces the file whole, so a read never sees it empty.
private func writtenChunks(in file: URL) -> (program: Int32?, chunks: Int) {
    let fields = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: " ").compactMap { Int32($0) }
    return (fields.first, Int(fields.last ?? 0))
}

/// The state of a process as `ps` shows it, such as "S" for a process that
/// sleeps and "R" for one that runs or waits for a processor.
private func processState(of processIdentifier: Int32) -> String? {
    let lister = Process()
    lister.executableURL = URL(fileURLWithPath: "/bin/ps")
    lister.arguments = ["-o", "stat=", "-p", "\(processIdentifier)"]
    let pipe = Pipe()
    lister.standardOutput = pipe
    lister.standardError = FileHandle.nullDevice
    guard (try? lister.run()) != nil else { return nil }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    lister.waitUntilExit()
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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

/// The summaries of the sessions, as the protocol lists them, or `nil`.
private func listedSummaries(_ process: RunningSessionProcess) throws -> [SessionSummary]? {
    let client = try greetedConnection(to: process.socketPath)
    defer { client.connection.shutdown() }
    try client.connection.send(ClientMessage.listSessions)
    guard case .sessionList(let summaries) = try receiveMessage(client.connection, within: 30) else { return nil }
    return summaries
}



private final class FloodReader: Sendable {
    struct State {
        var byteCount = 0
        var exit: SessionExit?
        var isDone = false
        var failure: String?
        var bytesBeforeSize: Int?
        var queriesSeen = 0
        var repliesSent = 0
    }
    let state = Mutex(State())
    private let connection: MessageConnection
    private let bytesPerSecond: Int?
    private let tracksQueries: Bool
    private let answersQueries: Bool
    init(_ connection: MessageConnection, bytesPerSecond: Int? = nil, tracksQueries: Bool = false, answersQueries: Bool = false) {
        self.connection = connection
        self.bytesPerSecond = bytesPerSecond
        self.tracksQueries = tracksQueries
        self.answersQueries = answersQueries
    }

    func start() {
        Thread { [self] in
            var bytesSincePause = 0
            var trailingBytes = Data()
            do {
                while let message = try connection.receive(ServerMessage.self) {
                    switch message {
                    case .output(let bytes):
                        state.withLock { $0.byteCount += bytes.count }
                        if tracksQueries {
                            let searchable = trailingBytes + bytes
                            if searchable.range(of: Data([0x1B, 0x5B, 0x63])) != nil {
                                state.withLock { $0.queriesSeen += 1 }
                                if answersQueries {
                                    try connection.send(ClientMessage.input(Data([0x1B, 0x5B, 0x3F, 0x36, 0x32, 0x3B, 0x32, 0x32, 0x63])))
                                    state.withLock { $0.repliesSent += 1 }
                                }
                            }
                            trailingBytes = Data(searchable.suffix(2))
                        }
                        bytesSincePause += bytes.count
                        if let bytesPerSecond, bytesSincePause >= 256 * 1024 {
                            Thread.sleep(forTimeInterval: Double(bytesSincePause) / Double(bytesPerSecond))
                            bytesSincePause = 0
                        }
                    case .exited(let exit):
                        state.withLock { $0.exit = exit }
                        state.withLock { $0.isDone = true }
                        return
                    case .sizeChanged:
                        state.withLock { $0.bytesBeforeSize = $0.byteCount }
                    default: break
                    }
                }
            } catch {
                state.withLock { $0.failure = "\(error)" }
            }
            state.withLock { $0.isDone = true }
        }.start()
    }
}
private func startFlood(_ process: RunningSessionProcess) throws -> (String, URL) {
    let go = process.directory.appendingPathComponent("flood-go")
    let script = "while [ ! -e '\(go.path)' ]; do sleep 0.02; done; exec /usr/bin/yes"
    return (try process.createSession(program: ["/bin/sh", "-c", script]), go)
}
/// Starts a session whose snapshot is larger than 1 MiB, so a client that
/// attaches gets the large-snapshot grace. The program prints a long
/// scrollback in many colors, waits for the file `go`, and then runs
/// `afterwards`, some Perl.
private func startLargeSnapshotSession(_ process: RunningSessionProcess, size: SessionSize, afterwards: String) async throws -> (identifier: String, go: URL) {
    let go = process.directory.appendingPathComponent("snapshot-go")
    let program = process.directory.appendingPathComponent("large-snapshot")
    let script = #"""
    $| = 1;
    for my $line (1 .. 1600) {
        my $text = '';
        for my $column (1 .. 239) {
            $text .= sprintf("\e[38;5;%dm%c", ($column * 7 + $line) % 256, 97 + ($column + $line) % 26);
        }
        print $text, "\e[0m\n";
    }
    print "snapshot-ready\n";
    while (! -e $ARGV[0]) { select(undef, undef, undef, 0.02); }
    \#(afterwards)
    """#
    try script.write(to: program, atomically: true, encoding: .utf8)
    let control = try greetedConnection(to: process.socketPath)
    defer { control.connection.shutdown() }
    try control.connection.send(ClientMessage.createSession(folder: process.directory.path,
        command: ["/usr/bin/perl", program.path, go.path], size: size, environment: ["PATH": "/usr/bin:/bin"]))
    guard case .sessionCreated(let summary) = try receiveMessage(control.connection, within: 30) else {
        throw SessionProtocolError.connectionClosed
    }
    let identifier = SessionSummary.text(for: summary.identifier)
    try #require(await process.waitForScreen(of: identifier, containing: "snapshot-ready", timeout: .seconds(120)))
    return (identifier, go)
}
private func attachFlood(_ process: RunningSessionProcess, identifier: String, size: SessionSize = SessionSize(columns: 80, rows: 24), waitsForOutputRoom: Bool, relaysRawOutput: Bool = false) throws -> (connection: MessageConnection, descriptor: Int32, snapshotByteCount: Int) {
    let client = try greetedConnection(to: process.socketPath)
    try client.connection.send(ClientMessage.attach(identifier: try #require(UUID(uuidString: identifier)),
        size: size, relaysRawOutput: relaysRawOutput, waitsForOutputRoom: waitsForOutputRoom))
    guard case .attached = try receiveMessage(client.connection, within: 15),
          case .snapshot(let snapshot) = try receiveMessage(client.connection, within: 15) else {
        client.connection.shutdown()
        throw SessionProtocolError.connectionClosed
    }
    return (client.connection, client.descriptor, snapshot.count)
}
extension SessionProcessIntegration {
    /// Each client costs a bounded amount: a thread, a descriptor, and memory
    /// for what it sends and receives. Deadlines end the clients that stop
    /// halfway, and a limit refuses clients past 64.
    @Suite struct ConnectionLimitTests {
        @Test(.tags(.takesEverySlot), arguments: [true, false])
        func aViewerThatDrainsAfterTheWaitTakesPrecedence(waitsForOutputRoom: Bool) async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try Session(
                summary: SessionSummary(identifier: UUID(), folder: "/", command: ["/bin/sleep"], size: size, createdAt: Date()),
                launch: ProgramLaunch(executablePath: "/bin/sleep", arguments: ["60"], folder: "/", environment: [:],
                    size: PseudoTerminalSize(columns: size.columns, rows: size.rows)),
                onFinish: { _ in }
            )
            await session.start()
            defer { Task { await session.terminate() } }

            let (slowSocket, slowPeer) = try MessageConnection.makePair()
            let (fastSocket, fastPeer) = try MessageConnection.makePair()
            let slow = ClientConnection(connection: slowSocket)
            let fast = ClientConnection(connection: fastSocket)
            defer { slowPeer.shutdown(); fastPeer.shutdown() }
            try slowPeer.greetSessionProcess()
            try fastPeer.greetSessionProcess()
            guard case .attached = try await session.attach(slow, size: size, relaysRawOutput: false,
                    receivesSizeChanges: false, waitsForOutputRoom: true),
                  case .attached = try await session.attach(fast, size: size, relaysRawOutput: false,
                    receivesSizeChanges: false, waitsForOutputRoom: waitsForOutputRoom),
                  case .attached = try receiveMessage(slowPeer, within: 10),
                  case .snapshot = try receiveMessage(slowPeer, within: 10),
                  case .attached = try receiveMessage(fastPeer, within: 10),
                  case .snapshot = try receiveMessage(fastPeer, within: 10) else {
                Issue.record("The clients did not attach.")
                return
            }

            fast.send(.output(Data(repeating: 65, count: ConnectionLimits.outputLowMark)))
            guard case .output = try receiveMessage(fastPeer, within: 10) else {
                Issue.record("The faster client did not receive its first output.")
                return
            }
            try #require(await eventually(timeout: .seconds(5)) { fast.hasMadeOutputProgress })
            fast.send(.output(Data(repeating: 66, count: 5 * 1024 * 1024)))
            slow.allowLargeSnapshotRestoration(byteCount: ConnectionLimits.largeSnapshotMinimumByteCount)
            slow.send(.output(Data(repeating: 67, count: ConnectionLimits.outputHighMark)))
            try #require(await eventually(timeout: .seconds(5)) {
                (slow.queuedOutputBytes ?? 0) >= ConnectionLimits.outputHighMark &&
                (fast.queuedOutputBytes ?? 0) > ConnectionLimits.outputLowMark
            })

            let wait = Task { await session.waitForOutputRoom() }
            try #require(await eventually(timeout: .seconds(5)) { slow.isWaitingForOutputRoom },
                "The slower client must be waiting before the faster client drains.")
            let start = ContinuousClock.now
            guard case .output = try receiveMessage(fastPeer, within: 10) else {
                Issue.record("The faster client did not drain its output.")
                return
            }
            let closed = await eventually(timeout: .seconds(1)) { slow.queuedOutputBytes == nil }
            print("viewer-progress-after-wait: closed \(closed) after \(ContinuousClock.now - start); waits \(waitsForOutputRoom)")
            #expect(closed, "A faster client must not wait for the slow client's snapshot grace.")
            #expect(!fastPeer.peerHasClosed)
            slowPeer.shutdown()
            await wait.value
        }
        @Test func aViewerThatMakesRoomBeforeTheCheckKeepsItsConnection() async throws {
            let (socket, peer) = try MessageConnection.makePair()
            let client = ClientConnection(connection: socket)
            defer { peer.shutdown() }
            try peer.greetSessionProcess()
            client.send(.output(Data(repeating: 65, count: ConnectionLimits.outputHighMark)))
            guard case .output = try receiveMessage(peer, within: 5) else {
                Issue.record("The client did not write its output.")
                return
            }
            try #require(await eventually(timeout: .seconds(5)) { client.queuedOutputBytes == 0 })
            client.endForOutputBackpressure()
            #expect(client.queuedOutputBytes != nil, "A client that made room must stay attached.")
        }

        @Test func aRefusedOutputRoomWaitReturnsAtOnce() async throws {
            let (socket, peer) = try MessageConnection.makePair()
            let client = ClientConnection(connection: socket)
            defer { peer.shutdown() }
            try peer.greetSessionProcess()
            client.send(.output(Data(repeating: 65, count: ConnectionLimits.outputHighMark)))
            try #require(await eventually(timeout: .seconds(5)) {
                (client.queuedOutputBytes ?? 0) >= ConnectionLimits.outputHighMark
            })
            client.refuseOutputRoomWait()
            let start = ContinuousClock.now
            await client.waitForOutputRoom(until: .now + ConnectionLimits.outputRoomTimeLimit)
            #expect(ContinuousClock.now - start < .seconds(1))
            #expect(client.queuedOutputBytes != nil)
        }
        @Test(.tags(.takesEverySlot)) func aProgramThatEndsWakesAFullViewer() async throws {
            try await RunningSessionProcess.run { process in
                // The program prints 10 MiB, more than the 7 MiB that fills the queue, and ends
                // while the session waits. The large snapshot gives the client 30 seconds from
                // the attach, so only the wake at the end of the program ends the wait sooner:
                // 2 seconds after the queue is full. A busy Mac took up to 20 seconds to
                // fill the queue, so the test now counts from the attach. Without the wake,
                // the session ends no sooner than 30 seconds after the attach. The client
                // takes a byte each 100 ms through a relay, so the write stall limit of
                // 10 seconds cannot end it first.
                let size = SessionSize(columns: 240, rows: 50)
                let (identifier, go) = try await startLargeSnapshotSession(process, size: size, afterwards: #"print "x" x 65536 for 1 .. 160;"#)
                let attached = ContinuousClock.now
                let client = try attachFlood(process, identifier: identifier, size: size, waitsForOutputRoom: true)
                defer { client.connection.shutdown() }
                try #require(client.snapshotByteCount >= ConnectionLimits.largeSnapshotMinimumByteCount, "The snapshot must give the client its grace.")
                let relay = try TrickleRelay(from: client.descriptor)
                defer { relay.connection.shutdown() }
                FileManager.default.createFile(atPath: go.path, contents: Data())
                let gone = await eventually(timeout: attached + .seconds(28) - ContinuousClock.now) { (try? process.listedIdentifiers())?.isEmpty == true }
                print("program-exit-wake: gone \(gone) after \(ContinuousClock.now - attached) from the attach")
                #expect(gone, "The session must end before the grace of 30 seconds.")
            }
        }

        @Test(.tags(.takesEverySlot)) func shutdownWakesAFullViewer() async throws {
            try await RunningSessionProcess.run { process in
                // The program ignores the hang-up of the shutdown, and the session kills it
                // after 1 second. The large snapshot keeps the client waiting for 30 seconds,
                // so only the wake of the shutdown makes the session read the program's
                // output again before the kill. The program counts the chunks it wrote, in a
                // file that it replaces whole, so a kill never leaves it empty. The
                // test once waited for all of its output, which a busy Mac did not write
                // within the second.
                let progress = process.directory.appendingPathComponent("progress")
                let size = SessionSize(columns: 240, rows: 50)
                let program = #"$SIG{HUP} = 'IGNORE'; for my $count (1 .. 256) { print "x" x 65536; open(my $file, '>', '\#(progress.path).new'); print $file "$$ $count"; close $file; rename('\#(progress.path).new', '\#(progress.path)'); }"#
                let (identifier, go) = try await startLargeSnapshotSession(process, size: size, afterwards: program)
                let stalled = try attachFlood(process, identifier: identifier, size: size, waitsForOutputRoom: true)
                defer { stalled.connection.shutdown() }
                try #require(stalled.snapshotByteCount >= ConnectionLimits.largeSnapshotMinimumByteCount, "The snapshot must give the client its grace.")
                let written = { ((try? String(contentsOf: progress, encoding: .utf8)) ?? "").split(separator: " ").compactMap { Int32($0) } }
                let writtenChunks = { Int(written().last ?? 0) }
                // A program that a busy Mac did not run also writes nothing, but
                // it is not asleep in a write.
                let programSleeps = { () -> Bool in
                    guard let program = written().first, let state = processState(of: program) else { return false }
                    return state.hasPrefix("S") || state.hasPrefix("I")
                }
                FileManager.default.createFile(atPath: go.path, contents: Data())
                // The session waits once the client's queue holds 7 MiB, 112 chunks.
                // The client takes a byte now and then, so the write stall limit of
                // 10 seconds does not end it while a busy Mac fills the queue.
                _ = fcntl(stalled.descriptor, F_SETFL, O_NONBLOCK)
                var chunksAtTheStop = 0, unchangedSince = ContinuousClock.now
                try #require(await eventually(timeout: .seconds(60)) {
                    var byte: UInt8 = 0
                    _ = Darwin.read(stalled.descriptor, &byte, 1)
                    let chunks = writtenChunks()
                    if chunks != chunksAtTheStop { (chunksAtTheStop, unchangedSince) = (chunks, .now) }
                    return chunks >= ConnectionLimits.outputHighMark / 65536 && ContinuousClock.now - unchangedSince >= .seconds(1) && programSleeps()
                }, "The program must stop in its output before the shutdown.")
                let start = ContinuousClock.now
                process.send(signal: SIGTERM)
                // Without the wake, the session process waits for the 30 seconds of grace.
                let exit = await process.waitForExit(timeout: 20)
                print("full-viewer-shutdown: exit \(String(describing: exit)) after \(ContinuousClock.now - start); chunks \(chunksAtTheStop) then \(writtenChunks())")
                #expect(exit != nil)
                #expect(writtenChunks() > chunksAtTheStop, "The session killed the program while it waited for room.")
            }
        }
        @Test(.tags(.takesEverySlot)) func aLargeSnapshotCanBeRestoredWhileOutputWaits() async throws {
            try await RunningSessionProcess.run { process in
                let size = SessionSize(columns: 240, rows: 50)
                let (identifier, go) = try await startLargeSnapshotSession(process, size: size, afterwards: #"exec "/usr/bin/yes";"#)
                let client = try greetedConnection(to: process.socketPath)
                defer { client.connection.shutdown() }
                try client.connection.send(ClientMessage.attach(identifier: try #require(UUID(uuidString: identifier)), size: size, waitsForOutputRoom: true))
                guard case .attached = try receiveMessage(client.connection, within: 30),
                      case .snapshot(let snapshot) = try receiveMessage(client.connection, within: 60) else {
                    Issue.record("The large snapshot did not arrive.")
                    return
                }
                try #require(snapshot.count >= 1024 * 1024, "The snapshot must exercise the large-snapshot grace period.")
                FileManager.default.createFile(atPath: go.path, contents: Data())
                try await Task.sleep(for: .seconds(3))
                #expect(!isClosedBySessionProcess(client.descriptor), "The client lost its connection while restoring the snapshot.")
                let terminal = try TerminalSnapshot(bytes: Array(snapshot)).restoreTerminal(scrollbackLimit: 10_000)
                let text = String(decoding: try terminal.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
                #expect(text.contains("snapshot-ready"))
                let reader = FloodReader(client.connection)
                reader.start()
                let advanced = await eventually(timeout: .seconds(8)) { reader.state.withLock { $0.byteCount > 1024 * 1024 || $0.isDone } }
                try client.connection.send(ClientMessage.input(Data([3])))
                let stopped = await eventually(timeout: .seconds(8)) { reader.state.withLock { $0.isDone } }
                let result = reader.state.withLock { $0 }
                print("large-snapshot-flow: \(snapshot.count) snapshot bytes; output \(result.byteCount); stopped \(stopped)")
                #expect(advanced && result.byteCount > 1024 * 1024)
                #expect(stopped && result.exit == .signaled(signal: SIGINT))
            }
        }

        @Test(.tags(.takesEverySlot)) func sustainedPacedFloodStaysAttachedAndAcceptsControlC() async throws {
            try await RunningSessionProcess.run { process in
                let (identifier, go) = try startFlood(process)
                let client = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true)
                defer { client.connection.shutdown() }
                let reader = FloodReader(client.connection, bytesPerSecond: 8 * 1024 * 1024)
                reader.start()
                let baseline = try #require(process.memoryFootprint)
                var maximum = baseline
                FileManager.default.createFile(atPath: go.path, contents: Data())
                // The test counts 30 MiB of output, not 10 seconds, because a
                // busy Mac moved less than 30 MiB in 10 seconds. The limit of
                // 120 seconds only stops a flood that does not move.
                let start = ContinuousClock.now
                while reader.state.withLock({ $0.byteCount }) <= 30 * 1024 * 1024 && ContinuousClock.now - start < .seconds(120) {
                    try await Task.sleep(for: .seconds(1))
                    maximum = max(maximum, try #require(process.memoryFootprint))
                    try #require(!reader.state.withLock { $0.isDone }, "The flood connection ended before control-C.")
                }
                let before = reader.state.withLock { $0.byteCount }
                try client.connection.send(ClientMessage.input(Data([3])))
                // The reader takes the output that waits before control-C at
                // its own pace, and a busy Mac read it at 0.5 MB a second, so
                // the stop took 7.5 seconds. The bytes after the key show that
                // the key did not wait behind the flood: 8 MiB of queue, 4 MiB
                // of read-ahead and the socket buffers hold less than 13 MiB.
                let stopped = await eventually(timeout: .seconds(30)) { reader.state.withLock { $0.isDone } }
                let result = reader.state.withLock { $0 }
                #expect(result.byteCount - before < 13 * 1024 * 1024)
                print("paced-flood: \(before) bytes; after \(result.byteCount - before); memory \(baseline) to \(maximum); stopped \(stopped); exit \(String(describing: result.exit))")
                #expect(before > 30 * 1024 * 1024)
                #expect(maximum - baseline < 128 * 1024 * 1024)
                #expect(stopped && result.exit == .signaled(signal: SIGINT))
                #expect(result.failure == nil)
            }
        }

        @Test(.tags(.takesEverySlot)) func resizeIsHandledWhileOutputWaitsAndStaysInOrder() async throws {
            try await RunningSessionProcess.run { process in
                let (identifier, go) = try startFlood(process)
                let client = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true)
                defer { client.connection.shutdown() }
                FileManager.default.createFile(atPath: go.path, contents: Data())
                try await Task.sleep(for: .milliseconds(750))
                let size = SessionSize(columns: 91, rows: 31)
                try client.connection.send(ClientMessage.resize(size, requestsConfirmation: true))
                let applied = try await eventually(timeout: .seconds(1)) {
                    try listedSummaries(process)?.first(where: { SessionSummary.text(for: $0.identifier) == identifier })?.size == size
                }
                let reader = FloodReader(client.connection)
                reader.start()
                let followed = await eventually(timeout: .seconds(6)) {
                    reader.state.withLock { state in state.bytesBeforeSize.map { state.byteCount > $0 } ?? state.isDone }
                }
                let before = reader.state.withLock { $0.byteCount }
                try client.connection.send(ClientMessage.input(Data([3])))
                // As in the paced flood test: on a busy Mac the reader took more
                // than 6 seconds for the output that waited before control-C.
                // Less than 13 MiB after the key shows that the key did not wait.
                let stopped = await eventually(timeout: .seconds(30)) { reader.state.withLock { $0.isDone } }
                let result = reader.state.withLock { $0 }
                #expect(result.byteCount - before < 13 * 1024 * 1024)
                #expect(applied && followed)
                #expect((result.bytesBeforeSize ?? 0) > 0 && result.byteCount > (result.bytesBeforeSize ?? Int.max))
                #expect(stopped && result.exit == .signaled(signal: SIGINT))
            }
        }

        @Test(.tags(.takesEverySlot)) func aDeadViewerDoesNotBlockAFasterViewer() async throws {
            try await RunningSessionProcess.run { process in
                let (identifier, go) = try startFlood(process)
                let stalled = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true)
                FileManager.default.createFile(atPath: go.path, contents: Data())
                // The first client stops reading before the second attaches.
                try await Task.sleep(for: .milliseconds(750))
                let active = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true)
                defer { stalled.connection.shutdown(); active.connection.shutdown() }
                let reader = FloodReader(active.connection)
                reader.start()
                let closed = await eventually(timeout: .seconds(8)) { isClosedBySessionProcess(stalled.descriptor) }
                let before = reader.state.withLock { $0.byteCount }
                let advanced = await eventually(timeout: .seconds(5)) { reader.state.withLock { $0.byteCount > before + 1024 * 1024 || $0.isDone } }
                let alive = reader.state.withLock { !$0.isDone }
                try active.connection.send(ClientMessage.input(Data([3])))
                let stopped = await eventually(timeout: .seconds(5)) { reader.state.withLock { $0.isDone } }
                let result = reader.state.withLock { $0 }
                print("multiple-viewers: stalled closed \(closed); active advanced \(advanced); bytes \(result.byteCount)")
                #expect(closed && advanced && alive)
                #expect(stopped && result.exit == .signaled(signal: SIGINT))
            }
        }

        @Test(.tags(.takesEverySlot), arguments: [true, false])
        func replyGateFollowsRelayingClientsWhileOutputWaits(terminalAnswers: Bool) async throws {
            try await RunningSessionProcess.run { process in
                let flood = process.directory.appendingPathComponent("query-flood")
                let first = process.directory.appendingPathComponent("query-first")
                let second = process.directory.appendingPathComponent("query-second")
                let script = """
                stty raw -echo opost
                printf 'READY\\n'
                while [ ! -e '\(flood.path)' ]; do sleep 0.02; done
                head -c 12582912 /dev/zero | tr '\\000' x
                round() {
                  while [ ! -e "$1" ]; do sleep 0.02; done
                  printf '\\033[c'
                  printf 'reply%s=' "$2"
                  dd bs=1 count=9 2>/dev/null | od -An -c
                  stty min 0 time 10
                  printf 'extra%s=%s\\n' "$2" "$(dd bs=1 count=64 2>/dev/null | wc -c | tr -d ' ')"
                  stty min 1 time 0
                  printf 'DONE%s\\n' "$2"
                }
                round '\(first.path)' 1
                round '\(second.path)' 2
                sleep 60
                """
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                try #require(await process.waitForScreen(of: identifier, containing: "READY"))
                let application = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true)
                defer { application.connection.shutdown() }
                FileManager.default.createFile(atPath: flood.path, contents: Data())
                try await Task.sleep(for: .milliseconds(750))
                let terminal = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true, relaysRawOutput: true)
                defer { terminal.connection.shutdown() }
                let terminalReader = FloodReader(terminal.connection, tracksQueries: true, answersQueries: terminalAnswers)
                terminalReader.start()
                let reader = FloodReader(application.connection)
                reader.start()
                FileManager.default.createFile(atPath: first.path, contents: Data())
                try #require(await eventually(timeout: .seconds(20)) { terminalReader.state.withLock { $0.queriesSeen == 1 || $0.isDone } })
                try #require(terminalReader.state.withLock { $0.queriesSeen == 1 && !$0.isDone })
                if !terminalAnswers {
                    try await Task.sleep(for: .seconds(2))
                    let premature = try process.screenText(of: identifier).contains("DONE1")
                    print("reply-gate-control: withheld terminal reply; program completed early \(premature)")
                    #expect(!premature, "The server must not answer while a terminal relays.")
                    try terminal.connection.send(ClientMessage.input(Data([0x1B, 0x5B, 0x3F, 0x36, 0x32, 0x3B, 0x32, 0x32, 0x63])))
                }
                try #require(await process.waitForScreen(of: identifier, containing: "DONE1", timeout: .seconds(20)))
                #expect(try process.screenText(of: identifier).contains("extra1=0"))
                #expect(terminalReader.state.withLock { $0.repliesSent == (terminalAnswers ? 1 : 0) })
                try terminal.connection.send(ClientMessage.detach)
                try #require(await eventually(timeout: .seconds(8)) { terminalReader.state.withLock { $0.isDone } })
                FileManager.default.createFile(atPath: second.path, contents: Data())
                try #require(await process.waitForScreen(of: identifier, containing: "DONE2"))
                let screen = try process.screenText(of: identifier)
                #expect(screen.contains("reply2="))
                #expect(screen.contains("extra2=0"))
                #expect(terminalReader.state.withLock { $0.repliesSent == (terminalAnswers ? 1 : 0) })
            }
        }

        @Test(.tags(.takesEverySlot)) func detachWakesAFullViewer() async throws {
            try await RunningSessionProcess.run { process in
                // The large snapshot keeps the client waiting for 30 seconds. Without the
                // wake of the detach, only the close of the connection ends the wait, at
                // the closing limit of 2 seconds. The program counts the chunks that it
                // wrote, so the test compares the program's progress with the close and
                // not with a clock that a busy Mac makes late.
                let progress = process.directory.appendingPathComponent("progress")
                let size = SessionSize(columns: 240, rows: 50)
                let program = #"for (my $count = 1; ; $count++) { print "x" x 65536; open(my $file, '>', '\#(progress.path).new'); print $file "$$ $count"; close $file; rename('\#(progress.path).new', '\#(progress.path)'); }"#
                let (identifier, go) = try await startLargeSnapshotSession(process, size: size, afterwards: program)
                let stalled = try attachFlood(process, identifier: identifier, size: size, waitsForOutputRoom: true)
                defer { stalled.connection.shutdown() }
                try #require(stalled.snapshotByteCount >= ConnectionLimits.largeSnapshotMinimumByteCount, "The snapshot must give the client its grace.")
                FileManager.default.createFile(atPath: go.path, contents: Data())
                // As in the shutdown test: a byte now and then keeps the client, and
                // the program must sleep in a write with a full queue.
                _ = fcntl(stalled.descriptor, F_SETFL, O_NONBLOCK)
                var chunksAtTheStop = 0, unchangedSince = ContinuousClock.now
                try #require(await eventually(timeout: .seconds(60)) {
                    var byte: UInt8 = 0
                    _ = Darwin.read(stalled.descriptor, &byte, 1)
                    let (program, chunks) = writtenChunks(in: progress)
                    if chunks != chunksAtTheStop { (chunksAtTheStop, unchangedSince) = (chunks, .now) }
                    let sleeps = program.flatMap(processState(of:)).map { $0.hasPrefix("S") || $0.hasPrefix("I") } ?? false
                    return chunks >= ConnectionLimits.outputHighMark / 65536 && ContinuousClock.now - unchangedSince >= .seconds(1) && sleeps
                }, "The program must stop in its output before the detach.")
                try stalled.connection.send(ClientMessage.detach)
                // A thread looks for the close each 0.5 ms and then reads the count.
                // Without the wake, the program writes again only after the close.
                let descriptor = stalled.descriptor
                let chunksAtTheClose = await BlockingWork.onNewThread { () -> Int? in
                    let deadline = ContinuousClock.now + .seconds(30)
                    while ContinuousClock.now < deadline {
                        if isClosedBySessionProcess(descriptor) { return writtenChunks(in: progress).chunks }
                        usleep(500)
                    }
                    return nil
                }
                print("detach-wake: chunks \(chunksAtTheStop) at the detach, \(String(describing: chunksAtTheClose)) at the close")
                // Eight chunks, so the end of the chunk that waited is not enough.
                #expect((chunksAtTheClose ?? 0) >= chunksAtTheStop + 8, "The detach must wake the session before the close.")
                let active = try attachFlood(process, identifier: identifier, size: size, waitsForOutputRoom: true)
                defer { active.connection.shutdown() }
                let reader = FloodReader(active.connection)
                reader.start()
                let advanced = await eventually(timeout: .seconds(30)) { reader.state.withLock { $0.byteCount > 1024 * 1024 || $0.isDone } }
                try active.connection.send(ClientMessage.input(Data([3])))
                // The output that waits for the client comes before the exit status.
                let stopped = await eventually(timeout: .seconds(30)) { reader.state.withLock { $0.isDone } }
                let result = reader.state.withLock { $0 }
                #expect(advanced && result.byteCount > 1024 * 1024)
                #expect(stopped && result.exit == .signaled(signal: SIGINT))
            }
        }

        /// The waits for the full clients ran one after another, so the program
        /// stopped for 2 seconds for each stalled client: about 6 seconds here.
        ///
        /// A busy Mac made the time to fill the queues longer, so a limit on
        /// the time from the go file to the closes failed. Waits in turn show
        /// as closes 2 seconds apart, and load does not move them apart. The
        /// program measures the pause itself: the longest time that one write
        /// of 64 KiB took. A late test thread does not move that time.
        @Test(.tags(.takesEverySlot)) func severalStalledViewersPauseTheProgramForTwoSecondsInTotal() async throws {
            try await RunningSessionProcess.run { process in
                let go = process.directory.appendingPathComponent("flood-go")
                let pause = process.directory.appendingPathComponent("pause")
                let program = #"use Time::HiRes 'time'; $| = 1; select(undef, undef, undef, 0.02) until -e $ARGV[0]; my $longest = 0; while (1) { my $start = time; print "y\n" x 32768; my $took = time - $start; next if $took <= $longest; $longest = $took; open(my $file, '>', "$ARGV[1].new"); print $file $longest; close $file; rename("$ARGV[1].new", $ARGV[1]); }"#
                let identifier = try process.createSession(program: ["/usr/bin/perl", "-e", program, go.path, pause.path])
                let stalled = try (0..<3).map { _ in try attachFlood(process, identifier: identifier, waitsForOutputRoom: true) }
                defer { stalled.forEach { $0.connection.shutdown() } }
                FileManager.default.createFile(atPath: go.path, contents: Data())
                let start = ContinuousClock.now
                var closedAt: [Int: ContinuousClock.Instant] = [:]
                let closed = await eventually(timeout: .seconds(60)) {
                    for (index, client) in stalled.enumerated() where closedAt[index] == nil && isClosedBySessionProcess(client.descriptor) {
                        closedAt[index] = .now
                    }
                    return closedAt.count == stalled.count
                }
                let first = closedAt.values.min() ?? start, last = closedAt.values.max() ?? start
                print("stalled-viewers: all closed \(closed) from \(first - start) to \(last - start)")
                #expect(closed, "Three stalled viewers must lose their connections.")
                // The pause starts after the queues are full, so load only makes this longer.
                #expect(first - start > .seconds(1.5), "The pause must last the 2 seconds that a viewer gets to make room.")
                // A test thread that runs late sees the closes later, not further apart.
                #expect(last - first < .seconds(2), "Three stalled viewers must lose their connections within one pause of 2 seconds.")
                // The program notes the pause when its write ends, after the closes.
                var longest = 0.0
                _ = await eventually(timeout: .seconds(30)) {
                    longest = Double((try? String(contentsOf: pause, encoding: .utf8)) ?? "") ?? 0
                    return longest >= 1.5
                }
                print("stalled-viewers: the longest write took \(longest) seconds")
                // The read-ahead of 4 MiB fills in a moment, so the write waits for
                // nearly all of the pause. Waits in turn, or a longer limit, take 6 s.
                #expect(longest >= 1.5 && longest < 4, "One pause of 2 seconds must stop the program.")
            }
        }

        @Test(.tags(.takesEverySlot)) func aTrickleCannotKeepAFullViewerAttached() async throws {
            try await RunningSessionProcess.run { process in
                let (identifier, go) = try startFlood(process)
                let stalled = try attachFlood(process, identifier: identifier, waitsForOutputRoom: true)
                defer { stalled.connection.shutdown() }
                _ = fcntl(stalled.descriptor, F_SETFL, O_NONBLOCK)
                FileManager.default.createFile(atPath: go.path, contents: Data())
                let start = ContinuousClock.now
                // A byte now and then resets the write stall limit, so without the
                // pause limit the viewer stays for good. This test proves only that
                // the pause ends such a viewer. The test of several stalled viewers
                // proves that a pause lasts 2 seconds. The time to fill the queue
                // comes first, and a busy Mac took more than 8 seconds.
                let closed = await eventually(timeout: .seconds(60)) {
                    var byte: UInt8 = 0
                    _ = Darwin.read(stalled.descriptor, &byte, 1)
                    return isClosedBySessionProcess(stalled.descriptor)
                }
                print("trickle-viewer: closed \(closed) after \(ContinuousClock.now - start)")
                #expect(closed)
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

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
        /// It waits for the real limits of about 30 seconds and uses little
        /// processor time, so it starts at once.
        @Test(.tags(.startsAtOnce)) func slowAndSilentConnectionsAreEndedOnTimeAndHoldLittleMemory() async throws {
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

        /// A client's place among the 64 was free as soon as
        /// it detached, while its socket and threads stayed for up to 2
        /// seconds more to send what still waited for it. Clients that attach,
        /// read nothing and detach, over and over, then held more sockets and
        /// threads than the limit allows.
        @Test func clientsThatAttachAndDetachFastHoldNoMoreSocketsThanTheLimit() async throws {
            try await RunningSessionProcess.run { process in
                // The scrollback makes each snapshot far larger than a socket
                // holds, so it waits for a client that reads nothing.
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 3000; exec sleep 600"])
                #expect(await process.waitForScreen(of: identifier, containing: "3000"))
                let descriptorsBefore = try #require(process.descriptorCount)
                let threadsBefore = try #require(process.threadCount)

                var clients: [MessageConnection] = []
                defer { clients.forEach { $0.shutdown() } }
                var refusals: Set<String> = []
                var mostDescriptors = descriptorsBefore
                var mostThreads = threadsBefore
                let start = ContinuousClock.now
                for _ in 0..<150 {
                    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                    do {
                        try connection.greetSessionProcess()
                    } catch {
                        refusals.insert("\(error)")
                        continue
                    }
                    try connection.send(ClientMessage.attach(identifier: UUID(uuidString: identifier)!, size: SessionSize(columns: 80, rows: 24)))
                    try connection.send(ClientMessage.detach)
                    // The client keeps its socket and reads nothing.
                    clients.append(connection)
                    mostDescriptors = max(mostDescriptors, process.descriptorCount ?? Int.max)
                    mostThreads = max(mostThreads, process.threadCount ?? Int.max)
                }
                let churn = ContinuousClock.now - start
                print("attach-detach-churn: \(clients.count) served and \(150 - clients.count) refused in \(churn); descriptors \(descriptorsBefore) then at most \(mostDescriptors); threads \(threadsBefore) then at most \(mostThreads)")

                // Each client costs one descriptor, one reading thread, and at
                // most one thread that writes.
                #expect(mostDescriptors <= descriptorsBefore + 64 + 4, "descriptors went from \(descriptorsBefore) to \(mostDescriptors)")
                #expect(mostThreads <= threadsBefore + 2 * 64 + 16, "threads went from \(threadsBefore) to \(mostThreads)")
                // The 65th client is still refused, with the reason.
                #expect(refusals.allSatisfy { $0.contains("64 clients") }, "refusals: \(refusals)")

                // A place frees within the closing limit of 2 seconds, so a new
                // client is served soon.
                let waitStart = ContinuousClock.now
                let served = await eventually(timeout: .seconds(4)) {
                    guard let connection = try? MessageConnection.connect(to: SocketLocation(path: process.socketPath)) else { return false }
                    defer { connection.shutdown() }
                    return (try? connection.greetSessionProcess()) != nil
                }
                print("attach-detach-churn: a new client was served \(ContinuousClock.now - waitStart) after the churn")
                #expect(served, "no new client was served within 4 seconds")
                // Every socket of the churn is closed within the closing limit.
                var descriptorsAfter = Int.max
                let released = await eventually(timeout: .seconds(5)) {
                    descriptorsAfter = process.descriptorCount ?? Int.max
                    return descriptorsAfter <= descriptorsBefore + 1
                }
                #expect(released, "descriptors \(descriptorsBefore) then \(descriptorsAfter)")
            }
        }

        /// Every control reply counted 256 bytes toward the
        /// 8 MiB of output that may wait for a client, whatever its size. A
        /// client that asked for large lists and read nothing was ended only
        /// by the 10-second write stall, with far more than 8 MiB queued.
        @Test func aClientThatAsksForLargeListsAndReadsNothingIsEndedAtTheOutputLimit() async throws {
            try await RunningSessionProcess.run { process in
                // Four sessions whose commands hold 256 KiB each make a list of
                // more than 1 MiB.
                let creator = try greetedConnection(to: process.socketPath)
                let argument = String(repeating: "a", count: 256 * 1024)
                for _ in 0..<4 {
                    try creator.connection.send(ClientMessage.createSession(
                        folder: process.directory.path,
                        command: ["/bin/sh", "-c", "exec sleep 600", argument],
                        size: SessionSize(columns: 80, rows: 24),
                        environment: [:]
                    ))
                    guard case .sessionCreated = try receiveMessage(creator.connection, within: 30) else {
                        Issue.record("A session with a long command was not created.")
                        return
                    }
                }
                creator.connection.shutdown()
                let summaries = try #require(try listedSummaries(process))
                let listSize = try ServerMessage.sessionList(summaries).frame().encoded().count
                #expect(listSize > 1024 * 1024)

                let client = try greetedConnection(to: process.socketPath)
                defer { client.connection.shutdown() }
                // 64 requests of 25 bytes ask for more than 64 MiB.
                for _ in 0..<64 {
                    try client.connection.send(ClientMessage.listSessions)
                }
                let start = ContinuousClock.now
                let ended = await eventually(timeout: .seconds(5)) { isClosedBySessionProcess(client.descriptor) }
                print("large-lists: a list of \(listSize) bytes; the client was ended: \(ended) after \(ContinuousClock.now - start)")
                #expect(ended, "a client with \(64 * listSize) bytes of lists waiting was still open after 5 seconds")
                #expect(process.isRunning)
                #expect(try process.runCommand(["list"]).status == 0)
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
            let served = await BlockingWork.onNewThread { () -> Int in
                var served = 0
                let deadline = Date().addingTimeInterval(4)
                for connection in waiting {
                    let watchdog = DispatchWorkItem { connection.shutdown() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + max(0.05, deadline.timeIntervalSinceNow), execute: watchdog)
                    if (try? connection.greetSessionProcess()) != nil { served += 1 }
                    watchdog.cancel()
                }
                return served
            }
            print("descriptor-limit: \(served) of \(waiting.count) waiting clients were served")
            #expect(served >= 10, "\(served) of the \(waiting.count) waiting clients were served")
        }
    }
}
