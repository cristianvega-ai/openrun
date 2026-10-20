import CryptoKit
import Darwin
import Foundation
@testable import SessionProcess
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing

private enum RawClientError: Error, CustomStringConvertible {
    case connectFailed(code: Int32)
    case unexpectedAnswer(String)

    var description: String {
        switch self {
        case .connectFailed(let code): "connect failed: \(String(cString: strerror(code)))"
        case .unexpectedAnswer(let text): text
        }
    }
}

/// A client that speaks the socket protocol directly, so a test can send more
/// text than a command line holds, and floods of input frames.
private final class RawClient: Sendable {
    let connection: MessageConnection
    /// The socket, kept to see when the session process closes its side.
    private let descriptor: Int32

    init(socketPath: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        // Set before connecting: once the other side has closed, the system
        // refuses the option, and a write would end the test with SIGPIPE.
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: socketPath.utf8.prefix($0.count - 1)) }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard descriptor >= 0, result == 0 else {
            let code = errno
            if descriptor >= 0 { close(descriptor) }
            throw RawClientError.connectFailed(code: code)
        }
        self.descriptor = descriptor
        connection = MessageConnection(descriptor: descriptor)
        try connection.greetSessionProcess()
    }

    /// Receives one message, or `nil` when the connection closes or the time
    /// limit passes. A test that waits too long fails instead of hanging.
    func receive(within limit: TimeInterval = 60) throws -> ServerMessage? {
        let watchdog = DispatchWorkItem { [connection] in connection.shutdown() }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
        defer { watchdog.cancel() }
        return try connection.receive(ServerMessage.self)
    }

    /// Sends `sendText` and returns the answer.
    func sendText(_ bytes: ArraySlice<UInt8>, to identifier: String) throws -> ServerMessage? {
        try connection.send(ClientMessage.sendText(identifier: UUID(uuidString: identifier)!, text: String(decoding: bytes, as: UTF8.self)))
        return try receive()
    }

    /// Attaches, and reads the attached message and the snapshot.
    func attach(to identifier: String, relaysRawOutput: Bool = false) throws {
        try connection.send(ClientMessage.attach(
            identifier: UUID(uuidString: identifier)!,
            size: SessionSize(columns: 80, rows: 24),
            relaysRawOutput: relaysRawOutput
        ))
        guard case .attached = try receive(within: 30) else { throw RawClientError.unexpectedAnswer("The first answer to attach was not attached.") }
        guard case .snapshot = try receive(within: 30) else { throw RawClientError.unexpectedAnswer("The second answer to attach was not a snapshot.") }
    }

    /// Leaves without a word, the way a client that crashes does.
    func vanish() {
        connection.shutdown()
    }

    /// Stops sending and keeps reading, so it still sees what the session
    /// process sends and when it closes the connection.
    func closeSendingSide() {
        Darwin.shutdown(descriptor, SHUT_WR)
    }

    /// Whether the session process has closed its side of the connection.
    var isClosedBySessionProcess: Bool {
        var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        return poll(&entry, 1, 0) > 0 && entry.revents & Int16(POLLHUP) != 0
    }
}

/// Letters and digits in a fixed order, so that a lost or moved piece changes
/// the checksum.
private func patternBytes(count: Int) -> [UInt8] {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789".utf8)
    var bytes = [UInt8](repeating: 0, count: count)
    var state: UInt32 = 54321
    for index in 0..<count {
        state = state &* 1_103_515_245 &+ 12345
        bytes[index] = alphabet[Int((state >> 16) % UInt32(alphabet.count))]
    }
    return bytes
}

/// Fills the 8 MiB input backlog of a program that reads nothing yet, with
/// text that the session process acknowledged.
private let fillerByteCount = 8 * 1024 * 1024

private func fillBacklog(of identifier: String, in process: RunningSessionProcess) throws {
    let filler = try RawClient(socketPath: process.socketPath)
    let piece = patternBytes(count: 1024 * 1024)
    for _ in 0..<(fillerByteCount / piece.count) {
        #expect(try filler.sendText(piece[...], to: identifier) == .acknowledged)
    }
}

/// The text that a test types after the step under test. The program copies
/// its input to a file and never stops on its own, so the test cannot wait for
/// silence. Waiting input goes in whole and in order, so input that should
/// have been dropped would stand in front of the marker and show.
private let endMarker = Array("END-OF-INPUT-MARK".utf8)

/// Types the end marker into the program from a new connection. It waits for
/// room, so the program must be reading, or must start to read, before it
/// returns.
private func sendEndMarker(to identifier: String, in process: RunningSessionProcess) throws {
    let client = try RawClient(socketPath: process.socketPath)
    #expect(try client.sendText(endMarker[...], to: identifier) == .acknowledged)
}

/// Waits until the file ends with the marker. It reads only the end of the
/// file, because the file holds megabytes.
private func fileEnds(_ file: URL, with marker: [UInt8], timeout: Duration) async -> Bool {
    await eventually(timeout: timeout) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= UInt64(marker.count) else { return false }
        try? handle.seek(toOffset: size - UInt64(marker.count))
        return (try? handle.readToEnd()).map { [UInt8]($0) == marker } ?? false
    }
}

/// The script of a program that prints `ready`, reads nothing until the go
/// file exists, runs `beforeReading`, and then copies all of its input to the
/// received file. It does not stop on its own: the test ends the copy with
/// `sendEndMarker`.
///
/// The program does not read the filler with `head -c`. On a terminal, `head`
/// reads through a buffer and can take bytes past its count, such as a reply
/// right behind the filler, and those bytes are lost. That made a test fail
/// now and then on a busy Mac, and it could hide input that leaked through.
private func scriptThatReadsEverything(goFile: URL, receivedFile: URL, beforeReading: String = "") -> String {
    "stty raw -echo opost; echo ready; while [ ! -e '\(goFile.path)' ]; do sleep 0.02; done; \(beforeReading)"
        + "dd bs=65536 2>/dev/null > '\(receivedFile.path)'"
}

/// Checks that the program read exactly the filler that `fillBacklog`
/// sent, and then exactly `after`.
private func expectReceived(in file: URL, fillerThen after: [UInt8], _ context: Comment) {
    let received = (try? Data(contentsOf: file)) ?? Data()
    var expected = Data(capacity: fillerByteCount + after.count)
    let piece = patternBytes(count: 1024 * 1024)
    for _ in 0..<(fillerByteCount / piece.count) { expected.append(contentsOf: piece) }
    expected.append(contentsOf: after)
    guard received != expected else { return }
    let receivedBytes = [UInt8](received)
    let expectedBytes = [UInt8](expected)
    let commonCount = min(receivedBytes.count, expectedBytes.count)
    let firstDifference = (0..<commonCount).first { receivedBytes[$0] != expectedBytes[$0] } ?? commonCount
    Issue.record(
        "\(context): the program read \(receivedBytes.count) bytes, not \(expectedBytes.count); they differ from byte \(firstDifference), where it read \(Array(receivedBytes.dropFirst(firstDifference).prefix(16)))"
    )
}

/// Sends messages on its own thread until the count is sent or a send fails,
/// and counts what went out.
private final class MessageFlood: Sendable {
    let sentBytes = Atomic<Int>(0)
    let sentMessages = Atomic<Int>(0)
    let isFinished = Atomic<Bool>(false)

    init(client: RawClient, message: ClientMessage, byteCount: Int, count: Int) {
        let thread = Thread { [self] in
            defer { isFinished.store(true, ordering: .sequentiallyConsistent) }
            while sentMessages.load(ordering: .sequentiallyConsistent) < count {
                guard (try? client.connection.send(message)) != nil else { return }
                sentBytes.add(byteCount, ordering: .sequentiallyConsistent)
                sentMessages.add(1, ordering: .sequentiallyConsistent)
            }
        }
        thread.start()
    }

    /// Input frames of `frameSize` bytes until `total` bytes are sent.
    convenience init(client: RawClient, frameSize: Int, total: Int) {
        self.init(client: client, message: .input(Data(patternBytes(count: frameSize))), byteCount: frameSize, count: total / frameSize)
    }

    /// Waits until no message went out for `steadyFor`, or the flood finished.
    func waitUntilStalled(timeout: Duration, steadyFor: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + timeout
        var last = -1
        var steadySince = ContinuousClock.now
        while ContinuousClock.now < deadline, !isFinished.load(ordering: .sequentiallyConsistent) {
            let now = sentBytes.load(ordering: .sequentiallyConsistent)
            if now != last {
                last = now
                steadySince = ContinuousClock.now
            } else if ContinuousClock.now - steadySince > steadyFor {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}

/// Reads a connection on its own thread until the session process closes it,
/// and keeps how it ended: a clean close between two frames, or an error.
private final class ClosedConnectionWatch: Sendable {
    enum Ending: Sendable, Equatable {
        case cleanClose
        case failed(String)
    }

    private let ending = Mutex<Ending?>(nil)

    init(client: RawClient) {
        let thread = Thread { [self] in
            let result: Ending
            do {
                while try client.connection.receive(ServerMessage.self) != nil {}
                result = .cleanClose
            } catch {
                result = .failed("\(error)")
            }
            ending.withLock { $0 = result }
        }
        thread.start()
    }

    /// How the connection ended, or `nil` while it is open.
    var result: Ending? { ending.withLock { $0 } }
}

/// How a test fills a client's read-ahead with input that the program does
/// not read: up to the limit of 1024 messages, or up to the limit of 1 MiB.
enum ReadAheadFilling: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case messages
    case bytes

    var testDescription: String { rawValue }

    /// Input frames that fill the read-ahead exactly while the program's
    /// backlog is full. Waiting input goes in in order, so the first frame,
    /// which is larger than the little room that the backlog has left, keeps
    /// every later frame waiting too.
    var frames: [ClientMessage] {
        switch self {
        case .messages:
            [.input(Data(patternBytes(count: 64 * 1024)))] + Array(repeating: .input(Data([UInt8(ascii: "m")])), count: 1023)
        case .bytes:
            // With its length field and kind, the frame is exactly 1 MiB.
            [.input(Data(patternBytes(count: 1024 * 1024 - 5)))]
        }
    }
}

/// The value of something that the system measures. A process always has
/// memory, threads and descriptors, so a zero or a missing value means that
/// the measurement failed, and a bound checked against it would prove nothing.
private func measured(_ value: Int?, _ what: String) throws -> Int {
    let value = try #require(value, "The system did not report \(what).")
    try #require(value > 0, "The system reported \(value) for \(what).")
    return value
}

extension SessionProcessIntegration {
    /// Input that a program has not read yet waits in the session process, up
    /// to 8 MiB. Past that, a writer waits for room. Nothing is dropped while
    /// its client is there. Input of a client that has left holds nothing.
    @Suite struct InputBacklogTests {
        @Test func moreTextThanTheBacklogHoldsReachesASlowReaderCompleteAndInOrder() async throws {
            try await RunningSessionProcess.run { process in
                let total = 10 * 1024 * 1024
                let file = process.directory.appendingPathComponent("received-checksum")
                // The program reads nothing for two seconds, so the text piles up
                // past the 8 MiB backlog before it reads.
                let script = "stty raw -echo; sleep 2; head -c \(total) | shasum -a 256 > '\(file.path)'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                let text = patternBytes(count: total)
                let client = try RawClient(socketPath: process.socketPath)

                var answers: [ServerMessage?] = []
                for offset in stride(from: 0, to: total, by: 512 * 1024) {
                    answers.append(try client.sendText(text[offset..<offset + 512 * 1024], to: identifier))
                }
                #expect(answers.allSatisfy { $0 == .acknowledged })

                let expected = SHA256.hash(data: text).map { String(format: "%02x", $0) }.joined()
                let arrived = await eventually(timeout: .seconds(30)) {
                    ((try? String(contentsOf: file, encoding: .utf8)) ?? "").hasPrefix(expected)
                }
                #expect(arrived, "the program read: \((try? String(contentsOf: file, encoding: .utf8)) ?? "nothing")")
            }
        }

        @Test func textThatWaitsWhenTheProgramEndsIsReportedAsAFailure() async throws {
            try await RunningSessionProcess.run { process in
                // The program never reads, and ends after four seconds.
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; sleep 4"])
                let client = try RawClient(socketPath: process.socketPath)
                let piece = patternBytes(count: 1024 * 1024)
                // This fills the backlog.
                for _ in 0..<8 {
                    #expect(try client.sendText(piece[...], to: identifier) == .acknowledged)
                }

                // This text waits for room. Other requests and other sessions go on meanwhile.
                let waitingText = String(decoding: patternBytes(count: 512 * 1024), as: UTF8.self)
                let waiting = Task.detached { try process.runCommand(["send", identifier, waitingText]) }
                try await Task.sleep(for: .milliseconds(300))
                #expect(try process.listedIdentifiers().contains(identifier))
                let other = try process.createSession(program: ["/bin/sh"])
                #expect(try process.runCommand(["send", other, "--enter", "echo other-$((6*7))"]).status == 0)
                #expect(await process.waitForScreen(of: other, containing: "other-42"))

                let result = try await waiting.value
                #expect(result.status == 1)
                #expect(result.standardError.contains("ended"), "standard error: \(result.standardError)")
            }
        }

        @Test func aClientThatFloodsInputMeetsBackpressureAndTheProcessStaysSmall() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; exec sleep 600"])
                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier)
                let before = try measured(process.memoryFootprint, "the memory footprint")
                let threadsBefore = try measured(process.threadCount, "the thread count")

                let total = 256 * 1024 * 1024
                let flood = MessageFlood(client: client, frameSize: 64 * 1024, total: total)
                defer { client.connection.shutdown() }
                await flood.waitUntilStalled(timeout: .seconds(30))
                let sent = flood.sentBytes.load(ordering: .sequentiallyConsistent)
                let after = try measured(process.memoryFootprint, "the memory footprint")
                let threadsAfter = try measured(process.threadCount, "the thread count")
                print("input-flood: sent \(sent) bytes before the sends stopped; memory footprint \(before) then \(after) bytes; threads \(threadsBefore) then \(threadsAfter)")

                // The sends stop soon after the 8 MiB backlog and the 1 MiB
                // read-ahead are full. They do not stop before: that would be a
                // smaller backlog than the design promises. A test machine
                // measured 9,371,648 bytes.
                #expect(sent >= 8 * 1024 * 1024, "sent only \(sent) bytes")
                #expect(sent < 10 * 1024 * 1024 + 512 * 1024, "sent \(sent) bytes")
                // The backlog and the read-ahead use about 10 MiB, and a test
                // machine measured 13 MiB more than before.
                #expect(after - before < 24 * 1024 * 1024, "the memory footprint grew from \(before) to \(after) bytes")
                #expect(threadsAfter <= threadsBefore + 4, "threads went from \(threadsBefore) to \(threadsAfter)")

                // The session process still serves other requests, and kill ends
                // the session whose input waits.
                #expect(try process.listedIdentifiers() == [identifier])
                #expect(try process.runCommand(["kill", identifier]).status == 0)
                #expect(try process.listedIdentifiers().isEmpty)
                #expect(await eventually(timeout: .seconds(10)) { flood.isFinished.load(ordering: .sequentiallyConsistent) })
            }
        }

        @Test func aClientWhoseInputWaitsCanDetachAndTheProcessCanStop() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let goFile = process.directory.appendingPathComponent("go")
            let receivedFile = process.directory.appendingPathComponent("received")
            let script = scriptThatReadsEverything(goFile: goFile, receivedFile: receivedFile)
            let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
            #expect(await process.waitForScreen(of: identifier, containing: "ready"))
            try fillBacklog(of: identifier, in: process)

            // The backlog is full, so this client's input waits.
            let client = try RawClient(socketPath: process.socketPath)
            try client.attach(to: identifier)
            try client.connection.send(ClientMessage.input(Data(patternBytes(count: 64 * 1024))))
            try client.connection.send(ClientMessage.detach)
            let closed = ClosedConnectionWatch(client: client)
            // The session process ends the connection cleanly. An error would
            // also end the reader, and must not pass for a detach.
            #expect(await eventually(timeout: .seconds(5)) { closed.result != nil })
            #expect(closed.result == .cleanClose, "the connection ended with \(String(describing: closed.result))")
            client.connection.shutdown()
            #expect(try process.listedIdentifiers() == [identifier])

            // The input that waited when the client left never reaches the
            // program. The program reads the filler and then nothing more.
            FileManager.default.createFile(atPath: goFile.path, contents: Data())
            try sendEndMarker(to: identifier, in: process)
            #expect(await fileEnds(receivedFile, with: endMarker, timeout: .seconds(60)))
            expectReceived(in: receivedFile, fillerThen: endMarker, "after the client with waiting input detached")

            // Stopping the process ends the program.
            process.send(signal: SIGTERM)
            #expect(await process.waitForExit(timeout: 10) == 0)
        }

        /// Each client that floods input and leaves used to leave its
        /// waiting input, and the thread that read it, behind for good.
        @Test func clientsThatFloodInputAndLeaveHoldNothingAndTheirInputNeverArrives() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let receivedFile = process.directory.appendingPathComponent("received")
                let script = scriptThatReadsEverything(goFile: goFile, receivedFile: receivedFile)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)

                var footprintAtStart = 0
                var threadsAtStart = 0
                var descriptorsAtStart = 0
                var sentPerCycle: [Int] = []
                for cycle in 1...30 {
                    let client = try RawClient(socketPath: process.socketPath)
                    try client.attach(to: identifier)
                    let flood = MessageFlood(client: client, frameSize: 64 * 1024, total: 8 * 1024 * 1024)
                    await flood.waitUntilStalled(timeout: .seconds(10), steadyFor: .milliseconds(150))
                    sentPerCycle.append(flood.sentBytes.load(ordering: .sequentiallyConsistent))
                    client.vanish()
                    #expect(await eventually(timeout: .seconds(5)) { flood.isFinished.load(ordering: .sequentiallyConsistent) })
                    if cycle == 3 {
                        try await Task.sleep(for: .milliseconds(500))
                        footprintAtStart = try measured(process.memoryFootprint, "the memory footprint")
                        threadsAtStart = try measured(process.threadCount, "the thread count")
                        descriptorsAtStart = try measured(process.descriptorCount, "the descriptor count")
                    }
                }
                try await Task.sleep(for: .milliseconds(500))
                let footprintAtEnd = try measured(process.memoryFootprint, "the memory footprint")
                let threadsAtEnd = try measured(process.threadCount, "the thread count")
                let descriptorsAtEnd = try measured(process.descriptorCount, "the descriptor count")
                print("flood-and-leave: sent per cycle \(sentPerCycle); footprint \(footprintAtStart) then \(footprintAtEnd); threads \(threadsAtStart) then \(threadsAtEnd); descriptors \(descriptorsAtStart) then \(descriptorsAtEnd)")

                // Each client met backpressure: the read-ahead filled and the
                // sends stopped long before the 8 MiB that the flood offered.
                #expect(sentPerCycle.allSatisfy { $0 >= 512 * 1024 && $0 < 4 * 1024 * 1024 }, "sent per cycle: \(sentPerCycle)")
                // 27 more clients came and left. They hold no memory, threads or descriptors.
                #expect(footprintAtEnd - footprintAtStart < 12 * 1024 * 1024, "footprint grew from \(footprintAtStart) to \(footprintAtEnd) bytes")
                #expect(threadsAtEnd <= threadsAtStart + 4, "threads went from \(threadsAtStart) to \(threadsAtEnd)")
                #expect(descriptorsAtEnd <= descriptorsAtStart + 2, "descriptors went from \(descriptorsAtStart) to \(descriptorsAtEnd)")

                // The program gets the filler, which was acknowledged, and none of
                // the input of the clients that left.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                try sendEndMarker(to: identifier, in: process)
                #expect(await fileEnds(receivedFile, with: endMarker, timeout: .seconds(60)))
                expectReceived(in: receivedFile, fillerThen: endMarker, "after the clients that flooded input left")
            }
        }

        /// A client whose read-ahead is full when its program ends still gets
        /// the exit status: the reading thread stops, and the queued messages
        /// go out before the connection closes.
        @Test func aClientWithAFullReadAheadStillGetsTheExitStatus() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let script = "stty raw -echo; echo ready; while [ ! -e '\(goFile.path)' ]; do sleep 0.1; done; exit 3"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)

                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier)
                let flood = MessageFlood(client: client, frameSize: 64 * 1024, total: 16 * 1024 * 1024)
                await flood.waitUntilStalled(timeout: .seconds(10), steadyFor: .milliseconds(300))
                let sent = flood.sentBytes.load(ordering: .sequentiallyConsistent)
                #expect(sent >= 512 * 1024 && sent < 4 * 1024 * 1024, "sent \(sent) bytes")

                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                var exit: SessionExit?
                while let message = try? client.receive(within: 30) {
                    if case .exited(let ended) = message { exit = ended }
                }
                #expect(exit == .exited(status: 3))
            }
        }

        /// A relaying client that vanished while its read-ahead was
        /// full stayed attached, so the session process never answered again.
        /// The program asks first and reads the filler later, so the reply
        /// waits behind the filler. Only a session process that noticed the
        /// vanished client on its own opens the way for it.
        ///
        /// The test measures when the session process closes the socket of
        /// the vanished client, and that must happen within a second. A fixed
        /// wait of 4 seconds before the program asked would also pass for a
        /// session process that took seconds to notice. The
        /// program reads its input into a file, because `head -c` lost the
        /// reply now and then on a busy Mac (see `scriptThatReadsEverything`).
        @Test func aRelayingClientThatVanishesWithAFullReadAheadNoLongerSilencesTheSession() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let receivedFile = process.directory.appendingPathComponent("received")
                let script = scriptThatReadsEverything(goFile: goFile, receivedFile: receivedFile, beforeReading: "printf '\\033[c'; echo asked; ")
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)

                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier, relaysRawOutput: true)
                let flood = MessageFlood(client: client, frameSize: 64 * 1024, total: 16 * 1024 * 1024)
                await flood.waitUntilStalled(timeout: .seconds(30), steadyFor: .seconds(1))
                let sent = flood.sentBytes.load(ordering: .sequentiallyConsistent)
                #expect(sent >= 512 * 1024 && sent < 4 * 1024 * 1024, "sent \(sent) bytes")
                let descriptorsBefore = try measured(process.descriptorCount, "the descriptor count")

                client.vanish()
                let vanished = ContinuousClock.now
                // The session process checks every 100 milliseconds whether the
                // client has left. Once it has, it detaches the client and closes
                // the client's socket.
                let noticed = await eventually(timeout: .seconds(1)) { (process.descriptorCount ?? Int.max) < descriptorsBefore }
                print("vanished-relaying-client: noticed \(noticed) after \(ContinuousClock.now - vanished)")
                #expect(noticed, "the session process did not notice within a second that the client vanished")

                // The program prints `asked` right after the query. The session
                // process reads the output in order, so when `asked` is on the
                // screen, the reply to the query is already on its way into the
                // backlog.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                #expect(await process.waitForScreen(of: identifier, containing: "asked", timeout: .seconds(60)))
                try sendEndMarker(to: identifier, in: process)
                #expect(await fileEnds(receivedFile, with: endMarker, timeout: .seconds(60)))
                // The session process answered the query, and none of the input
                // of the vanished client arrived.
                expectReceived(in: receivedFile, fillerThen: Array("\u{1B}[?62;22c".utf8) + endMarker, "after the relaying client vanished")
            }
        }

        /// Requests counted 256 bytes at any size, so a client could
        /// make the session process read and decode without limit.
        @Test func aFloodOfRequestsWithLargeEnvironmentsMeetsTheReadAheadLimit() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; exec sleep 600"])
                try fillBacklog(of: identifier, in: process)

                // This text waits for room, so the session process handles no
                // later request of this client until the program reads.
                let client = try RawClient(socketPath: process.socketPath)
                try client.connection.send(ClientMessage.sendText(identifier: UUID(uuidString: identifier)!, text: String(repeating: "w", count: 64 * 1024)))
                try await Task.sleep(for: .milliseconds(300))
                let footprintBefore = try measured(process.memoryFootprint, "the memory footprint")
                let threadsBefore = try measured(process.threadCount, "the thread count")

                var environment: [String: String] = [:]
                for number in 0..<16_384 {
                    environment["VARIABLE_\(number)"] = String(repeating: "v", count: 48)
                }
                let request = ClientMessage.createSession(folder: "/", command: ["/usr/bin/true"], size: SessionSize(columns: 0, rows: 0), environment: environment)
                let requestSize = try request.frame().encoded().count
                let flood = MessageFlood(client: client, message: request, byteCount: requestSize, count: 48)
                await flood.waitUntilStalled(timeout: .seconds(60), steadyFor: .milliseconds(1500))
                let sent = flood.sentMessages.load(ordering: .sequentiallyConsistent)
                let footprintAfter = try measured(process.memoryFootprint, "the memory footprint")
                let threadsAfter = try measured(process.threadCount, "the thread count")
                print("environment-flood: \(sent) requests of \(requestSize) bytes went out; footprint \(footprintBefore) then \(footprintAfter); threads \(threadsBefore) then \(threadsAfter)")

                #expect(sent <= 2, "\(sent) requests of \(requestSize) bytes went out")
                #expect(footprintAfter - footprintBefore < 32 * 1024 * 1024, "footprint grew from \(footprintBefore) to \(footprintAfter) bytes")
                #expect(threadsAfter <= threadsBefore + 4, "threads went from \(threadsBefore) to \(threadsAfter)")

                client.vanish()
                #expect(try process.runCommand(["kill", identifier]).status == 0)
                #expect(try process.listedIdentifiers().isEmpty)
            }
        }

        /// The sendText call went around the typed input of its own
        /// connection, so the program read them out of order.
        @Test func sendTextWaitsBehindTheTypedInputOfItsOwnConnection() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let receivedFile = process.directory.appendingPathComponent("received")
                let script = scriptThatReadsEverything(goFile: goFile, receivedFile: receivedFile)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)

                // Two input frames and then sendText, all on one attached
                // connection, all waiting for room.
                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier)
                try client.connection.send(ClientMessage.input(Data(repeating: UInt8(ascii: "a"), count: 64 * 1024)))
                try client.connection.send(ClientMessage.input(Data(repeating: UInt8(ascii: "c"), count: 64 * 1024)))
                try client.connection.send(ClientMessage.sendText(identifier: UUID(uuidString: identifier)!, text: String(repeating: "b", count: 64 * 1024)))
                try await Task.sleep(for: .milliseconds(300))

                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                var answer: ServerMessage?
                while let message = try client.receive(within: 60) {
                    if case .output = message { continue }
                    answer = message
                    break
                }
                #expect(answer == .acknowledged)
                try sendEndMarker(to: identifier, in: process)
                #expect(await fileEnds(receivedFile, with: endMarker, timeout: .seconds(60)))
                let inOrder = [UInt8(ascii: "a"), UInt8(ascii: "c"), UInt8(ascii: "b")].flatMap { Array(repeating: $0, count: 64 * 1024) }
                expectReceived(in: receivedFile, fillerThen: inOrder + endMarker, "after the input frames and the sent text")
            }
        }

        /// The limit of 1024 messages in the
        /// read-ahead had no test, and the suite stayed green without it. One-byte frames
        /// that wait for the program reach that limit long before 1 MiB.
        @Test func aFloodOfTinyInputFramesMeetsTheMessageLimitOfTheReadAhead() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; echo ready; exec sleep 600"])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)
                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier)
                // This frame does not fit the room that the backlog has left, so
                // every frame after it waits too.
                try client.connection.send(ClientMessage.input(Data(patternBytes(count: 64 * 1024))))

                let offered = 20_000
                let flood = MessageFlood(client: client, message: .input(Data([UInt8(ascii: "t")])), byteCount: 1, count: offered)
                defer { client.connection.shutdown() }
                await flood.waitUntilStalled(timeout: .seconds(30))
                let sent = flood.sentMessages.load(ordering: .sequentiallyConsistent)
                print("tiny-input-flood: \(sent) of \(offered) one-byte frames went out before the sends stopped")

                // 1023 frames fit behind the first one, and the socket holds a few
                // hundred more. A test machine measured about 1280 in all. Without
                // the message limit, all 20,000 go out, because they hold only
                // 120,000 bytes.
                #expect(sent >= 1023, "only \(sent) frames went out")
                #expect(sent < 4096, "\(sent) of \(offered) one-byte frames went out")
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        /// A client whose read-ahead was full of input that its
        /// program did not read could not detach. The detach behind the input
        /// waited until the program read.
        @Test(arguments: ReadAheadFilling.allCases)
        func aClientWhoseReadAheadIsFullOfInputCanStillDetach(filling: ReadAheadFilling) async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let receivedFile = process.directory.appendingPathComponent("received")
                let script = scriptThatReadsEverything(goFile: goFile, receivedFile: receivedFile)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)

                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier)
                for frame in filling.frames {
                    try client.connection.send(frame)
                }
                try client.connection.send(ClientMessage.detach)
                let closed = ClosedConnectionWatch(client: client)
                let start = ContinuousClock.now
                let ended = await eventually(timeout: .seconds(5)) { closed.result != nil }
                print("full-read-ahead-detach (\(filling.rawValue)): ended \(ended) after \(ContinuousClock.now - start) with \(String(describing: closed.result))")
                #expect(ended, "the session process did not handle the detach behind a read-ahead full of \(filling.rawValue)")
                #expect(closed.result == .cleanClose, "the connection ended with \(String(describing: closed.result))")
                client.connection.shutdown()
                #expect(try process.listedIdentifiers() == [identifier])

                // The input that waited when the client detached never reaches
                // the program.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                try sendEndMarker(to: identifier, in: process)
                #expect(await fileEnds(receivedFile, with: endMarker, timeout: .seconds(60)))
                expectReceived(in: receivedFile, fillerThen: endMarker, "after the detach behind a read-ahead full of \(filling.rawValue)")
            }
        }

        /// The session process must notice a client that shuts down only
        /// its sending side while its read-ahead is full. macOS reports
        /// such a socket as closed by the
        /// peer, so the client counts as gone, as one that closes between two
        /// frames does: it is detached, its waiting input is dropped, and it
        /// still reads the clean end of the connection.
        @Test func aClientThatStopsSendingWithAFullReadAheadIsDetachedAtOnce() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let receivedFile = process.directory.appendingPathComponent("received")
                let script = scriptThatReadsEverything(goFile: goFile, receivedFile: receivedFile)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                try fillBacklog(of: identifier, in: process)

                let client = try RawClient(socketPath: process.socketPath)
                try client.attach(to: identifier, relaysRawOutput: true)
                let flood = MessageFlood(client: client, frameSize: 64 * 1024, total: 16 * 1024 * 1024)
                await flood.waitUntilStalled(timeout: .seconds(30), steadyFor: .seconds(1))
                let sent = flood.sentBytes.load(ordering: .sequentiallyConsistent)
                #expect(sent >= 512 * 1024 && sent < 4 * 1024 * 1024, "sent \(sent) bytes")

                let closed = ClosedConnectionWatch(client: client)
                client.closeSendingSide()
                let start = ContinuousClock.now
                let ended = await eventually(timeout: .seconds(1)) { closed.result != nil }
                print("half-close: the session process ended the connection: \(ended) after \(ContinuousClock.now - start) with \(String(describing: closed.result))")
                #expect(ended, "the session process did not notice within a second that the client stopped sending")
                #expect(closed.result == .cleanClose, "the connection ended with \(String(describing: closed.result))")
                client.connection.shutdown()
                #expect(try process.listedIdentifiers() == [identifier])

                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                try sendEndMarker(to: identifier, in: process)
                #expect(await fileEnds(receivedFile, with: endMarker, timeout: .seconds(60)))
                expectReceived(in: receivedFile, fillerThen: endMarker, "after the client stopped sending")
            }
        }

        /// A reading thread that waits for room must notice
        /// a client that left within a second, whenever in its wait the client
        /// leaves. Here the client leaves 300 milliseconds into the wait, so a
        /// check that comes only every few seconds fails every time.
        @Test func aReadingThreadThatWaitsForRoomNoticesWithinASecondThatItsClientLeft() async throws {
            let readAhead = ReadAhead()
            for _ in 0..<ConnectionLimits.readAheadMessageLimit {
                #expect(readAhead.admit(6, isControl: false, peerHasClosed: { false }) == .shared)
            }
            let clientHasLeft = Atomic<Bool>(false)
            let ending = Mutex<(admitted: ReadAhead.Room?, at: ContinuousClock.Instant)?>(nil)
            let thread = Thread {
                let admitted = readAhead.admit(6, isControl: false) { clientHasLeft.load(ordering: .sequentiallyConsistent) }
                ending.withLock { $0 = (admitted, ContinuousClock.now) }
            }
            thread.start()
            try await Task.sleep(for: .milliseconds(300))
            #expect(ending.withLock { $0 } == nil, "the thread did not wait for room")
            clientHasLeft.store(true, ordering: .sequentiallyConsistent)
            let left = ContinuousClock.now
            let noticed = await eventually(timeout: .seconds(5)) { ending.withLock { $0 } != nil }
            let result = ending.withLock { $0 }
            print("read-ahead-wait: the thread returned \(String(describing: result?.admitted)) \(result.map { $0.at - left } ?? .seconds(5)) after the client left")
            #expect(noticed && result?.admitted == nil, "the waiting thread was not told that its client left")
            #expect((result?.at ?? .now) - left < .seconds(1), "the waiting thread noticed after \(String(describing: result.map { $0.at - left }))")
        }

        /// The reserve takes one control frame of at most 1 KiB
        /// past a read-ahead that is full by messages or by bytes. Input never
        /// takes it, a larger control frame never takes it, and it holds one
        /// frame at a time, so the read-ahead stays bounded.
        @Test func theReserveOfTheReadAheadTakesOneSmallControlFrameAndNeverInput() {
            // A client that leaves ends each wait for room that cannot succeed.
            let leaving: () -> Bool = { true }
            let fullByMessages = ReadAhead()
            for _ in 0..<ConnectionLimits.readAheadMessageLimit {
                #expect(fullByMessages.admit(6, isControl: false, peerHasClosed: leaving) == .shared)
            }
            #expect(fullByMessages.admit(6, isControl: false, peerHasClosed: leaving) == nil, "input went past the limit")
            #expect(fullByMessages.admit(18, isControl: true, peerHasClosed: leaving) == .reserve, "a detach found no room")
            #expect(fullByMessages.admit(18, isControl: true, peerHasClosed: leaving) == nil, "the reserve took a second frame")
            fullByMessages.release(18, from: .reserve)
            #expect(fullByMessages.admit(1025, isControl: true, peerHasClosed: leaving) == nil, "the reserve took a frame above 1 KiB")
            #expect(fullByMessages.admit(1024, isControl: true, peerHasClosed: leaving) == .reserve)
            fullByMessages.release(6, from: .shared)
            #expect(fullByMessages.admit(6, isControl: false, peerHasClosed: leaving) == .shared, "a handled frame did not free its room")

            let fullByBytes = ReadAhead()
            #expect(fullByBytes.admit(ConnectionLimits.readAheadByteLimit, isControl: false, peerHasClosed: leaving) == .shared)
            #expect(fullByBytes.admit(6, isControl: false, peerHasClosed: leaving) == nil, "input went past the byte limit")
            #expect(fullByBytes.admit(18, isControl: true, peerHasClosed: leaving) == .reserve, "a detach found no room")
        }
    }
}
