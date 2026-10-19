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

/// The lines of a screen, so a test can match a whole line.
private func lines(of screen: String) -> [String] {
    screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
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
