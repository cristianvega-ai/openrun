import Darwin
import Foundation
import Synchronization
import Testing
@testable import SessionProtocol

/// Runs one `receive` on a thread of its own and keeps how it ended.
private final class BlockedReader: Sendable {
    enum Ending: Sendable, Equatable {
        /// `receive` returned `nil`: the connection ended between two frames.
        case cleanEnd
        /// `receive` returned a message, which no test here expects.
        case message
        /// `receive` threw; the text is the description of the error.
        case failed(String)
    }

    private let state = Mutex<(threadIdentifier: UInt64, ending: Ending?)>((0, nil))
    private let work: @Sendable () throws -> Bool

    /// - Parameter receive: One receive call; the result says whether a
    ///   message arrived.
    init<Message: Sendable>(_ receive: @escaping @Sendable () throws -> Message?) {
        work = { try receive() != nil }
    }

    func start() {
        let thread = Thread { [self] in
            var identifier: UInt64 = 0
            pthread_threadid_np(nil, &identifier)
            state.withLock { $0.threadIdentifier = identifier }
            let result: Ending
            do {
                result = try work() ? .message : .cleanEnd
            } catch {
                result = .failed("\(error)")
            }
            state.withLock { $0.ending = result }
        }
        thread.start()
    }

    var ending: Ending? { state.withLock { $0.ending } }

    /// Whether the system shows the thread waiting in a system call.
    var isBlocked: Bool {
        let identifier = state.withLock { $0.threadIdentifier }
        guard identifier != 0 else { return false }
        var information = proc_threadinfo()
        let size = Int32(MemoryLayout<proc_threadinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTHREADID64INFO, identifier, &information, size) == size else { return false }
        return information.pth_run_state == TH_STATE_WAITING
    }
}

/// Polls until the condition holds or the timeout passes.
private func poll(timeout: Duration, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@Suite struct MessageConnectionTests {
    @Test func messagesTravelInBothDirections() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.listSessions)
        #expect(try server.receive(ClientMessage.self) == .listSessions)
        try server.send(ServerMessage.acknowledged)
        #expect(try client.receive(ServerMessage.self) == .acknowledged)
    }

    @Test func framesKeepTheirOrder() throws {
        let (client, server) = try MessageConnection.makePair()
        for number in 0..<50 {
            try client.send(ClientMessage.input(Data([UInt8(number)])))
        }
        for number in 0..<50 {
            #expect(try server.receive(ClientMessage.self) == .input(Data([UInt8(number)])))
        }
    }

    @Test func aLargePayloadArrivesWhole() throws {
        let (client, server) = try MessageConnection.makePair()
        let payload = Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: $0) })
        // The socket buffer is smaller, so sending needs a reader at the same time.
        let sender = Thread { try? client.send(ServerMessage.snapshot(payload)) }
        sender.start()
        #expect(try server.receive(ServerMessage.self) == .snapshot(payload))
    }

    @Test func aCleanCloseBetweenFramesGivesNil() throws {
        let (client, server) = try MessageConnection.makePair()
        client.shutdown()
        #expect(try server.receive(ClientMessage.self) == nil)
    }

    @Test func aCloseInTheMiddleOfAFrameThrows() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let receiver = MessageConnection(descriptor: descriptors[1])
        // A length field that promises 10 bytes, and only 2 follow.
        let partial: [UInt8] = [0, 0, 0, 10, 2, 7]
        #expect(write(descriptors[0], partial, partial.count) == partial.count)
        close(descriptors[0])
        #expect(throws: SessionProtocolError.connectionClosed) { try receiver.receive(ServerMessage.self) }
    }

    @Test func anOversizedLengthIsRejectedWithoutReadingTheBody() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let receiver = MessageConnection(descriptor: descriptors[1])
        defer { close(descriptors[0]) }
        let huge: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        #expect(write(descriptors[0], huge, huge.count) == huge.count)
        #expect(throws: SessionProtocolError.self) { try receiver.receive(ClientMessage.self) }
    }

    @Test func shutdownWakesAThreadThatIsWaitingWithACleanEnd() async throws {
        let (client, server) = try MessageConnection.makePair()
        let reader = BlockedReader { try server.receive(ClientMessage.self) }
        reader.start()

        // The peer is open and sends nothing, so the reader can only be
        // blocked in its read. Asking the system for the state of the thread
        // proves it, where a sleep would only hope for it.
        #expect(await poll(timeout: .seconds(10)) { reader.isBlocked }, "the reader never blocked")
        #expect(reader.ending == nil, "the reader ended before the shutdown: \(String(describing: reader.ending))")

        server.shutdown()
        #expect(await poll(timeout: .seconds(10)) { reader.ending != nil }, "the shutdown did not wake the reader")
        // A throw would also end the reader. The contract is a clean end,
        // which the session process reads as a client that left.
        #expect(reader.ending == .cleanEnd)
        withExtendedLifetime(client) {}
    }

    @Test func shutdownWakesAThreadInTheMiddleOfAFrameWithAnError() async throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        // A length field that promises 10 bytes, and only 2 follow.
        let partial: [UInt8] = [0, 0, 0, 10, 2, 7]
        #expect(write(descriptors[0], partial, partial.count) == partial.count)
        let reader = BlockedReader { try receiver.receive(ServerMessage.self) }
        reader.start()
        #expect(await poll(timeout: .seconds(10)) { reader.isBlocked }, "the reader never blocked")
        #expect(reader.ending == nil)

        receiver.shutdown()
        #expect(await poll(timeout: .seconds(10)) { reader.ending != nil }, "the shutdown did not wake the reader")
        #expect(reader.ending == .failed("\(SessionProtocolError.connectionClosed)"))
    }

    @Test func writingToAClosedPeerThrowsInsteadOfEndingTheProcess() throws {
        // Dropping the other end closes its descriptor.
        try whileNoChildStarts {
            let (client, _) = try MessageConnection.makePair()
            #expect(throws: SessionProtocolError.self) {
                for _ in 0..<10 { try client.send(ClientMessage.listSessions) }
            }
        }
    }

    @Test func theHandshakeAcceptsMatchingVersions() throws {
        let (client, server) = try MessageConnection.makePair()
        let greeter = Thread { try? server.greetClient() }
        greeter.start()
        try client.greetSessionProcess()
    }

    @Test func aClientWithAnotherVersionGetsAnIncompatibleFailure() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.hello(protocolVersion: 99))
        #expect(throws: SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: 99)) {
            try server.greetClient()
        }
        guard case .failure(let failure) = try client.receive(ServerMessage.self) else {
            Issue.record("The client received no failure.")
            return
        }
        #expect(failure.reason == .incompatibleProtocol)
    }

    @Test func aServerWithAnotherVersionIsDetectedByTheClient() throws {
        let (client, server) = try MessageConnection.makePair()
        try server.send(ServerMessage.hello(protocolVersion: 7))
        #expect(throws: SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: 7)) {
            try client.greetSessionProcess()
        }
    }

    /// A client that the session process refused for its
    /// version said that the session process speaks version 0.
    @Test func aRefusedClientNamesTheVersionThatTheSessionProcessSpeaks() throws {
        let (client, server) = try MessageConnection.makePair()
        try server.send(ServerMessage.failure(SessionFailure(
            reason: .incompatibleProtocol,
            message: "This session process speaks protocol version 2, not 1."
        )))
        #expect(throws: SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: 2)) {
            try client.greetSessionProcess()
        }
    }

    @Test func theRefusalOfTheSessionProcessNamesItsOwnVersion() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.hello(protocolVersion: 99))
        _ = try? server.greetClient()
        guard case .failure(let failure) = try client.receive(ServerMessage.self) else {
            Issue.record("The client received no failure.")
            return
        }
        #expect(failure.message.contains("protocol version \(MessageFrame.protocolVersion),"))
    }

    @Test func aConversationThatDoesNotStartWithHelloIsRefused() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.listSessions)
        #expect(throws: SessionProtocolError.self) { try server.greetClient() }
    }

    @Test func aFrameThatStallsEndsTheReceiveAfterTheStallLimit() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        // A length field that promises 64 MiB, and ten bytes of it.
        let partial: [UInt8] = [0x04, 0x00, 0x00, 0x01, 3] + [UInt8](repeating: 0x61, count: 10)
        #expect(write(descriptors[0], partial, partial.count) == partial.count)
        let start = ContinuousClock.now
        #expect(throws: SessionProtocolError.timedOut(waitingFor: "the rest of a frame")) {
            try receiver.receive(ClientMessage.self, timeLimit: .stall(.milliseconds(200)))
        }
        #expect(ContinuousClock.now - start >= .milliseconds(200))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aStallLimitDoesNotEndTheWaitBetweenFrames() throws {
        let (client, server) = try MessageConnection.makePair()
        let sender = Thread {
            Thread.sleep(forTimeInterval: 0.4)
            try? client.send(ClientMessage.listSessions)
        }
        sender.start()
        #expect(try server.receive(ClientMessage.self, timeLimit: .stall(.milliseconds(100))) == .listSessions)
    }

    @Test func theAdmissionOfAFrameSeesItsSizeAndKindBeforeTheBody() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.input(Data(repeating: 7, count: 1000)))
        var admitted = 0
        var admittedKind: MessageFrame.Kind?
        #expect(try server.receive(ClientMessage.self) { admitted = $0; admittedKind = $1 } == .input(Data(repeating: 7, count: 1000)))
        // The length field, the kind, and the payload.
        #expect(admitted == 4 + 1 + 1000)
        #expect(admittedKind == .input)
        try client.send(ClientMessage.detach)
        #expect(try server.receive(ClientMessage.self) { admittedKind = $1 } == .detach)
        #expect(admittedKind == .control)
        try client.send(ClientMessage.listSessions)
        #expect(throws: SessionProtocolError.connectionClosed) {
            try server.receive(ClientMessage.self) { _, _ in throw SessionProtocolError.connectionClosed }
        }
    }

    /// The session process gives a small control frame room that input
    /// cannot take, so it must know the kind before it waits for room. Here
    /// only the length field and the kind arrive. The admission still runs.
    @Test func theAdmissionRunsBeforeAnyByteOfThePayloadArrives() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        // A control frame that announces 100 bytes of payload, and none of them.
        let start: [UInt8] = [0, 0, 0, 101, 1]
        #expect(write(descriptors[0], start, start.count) == start.count)
        var admitted: (byteCount: Int, kind: MessageFrame.Kind)?
        #expect(throws: SessionProtocolError.connectionClosed) {
            try receiver.receive(ClientMessage.self, timeLimit: .stall(.seconds(5))) { byteCount, kind in
                admitted = (byteCount, kind)
                throw SessionProtocolError.connectionClosed
            }
        }
        #expect(admitted?.byteCount == 4 + 101)
        #expect(admitted?.kind == .control)
    }

    @Test func anUnknownKindIsRefusedBeforeTheAdmission() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        let frame: [UInt8] = [0, 0, 0, 3, 99, 1, 2]
        #expect(write(descriptors[0], frame, frame.count) == frame.count)
        var admissions = 0
        #expect(throws: SessionProtocolError.malformedFrame(reason: "the kind byte 99 is unknown")) {
            try receiver.receive(ClientMessage.self) { _, _ in admissions += 1 }
        }
        #expect(admissions == 0)
    }

    // The errors embedded the whole unexpected message. A
    // screen can be 64 MiB, and a request can hold text that a user typed or
    // escape sequences that drive the terminal that shows the error.

    @Test func anUnexpectedAnswerToHelloIsNamedWithoutItsContents() throws {
        let (client, server) = try MessageConnection.makePair()
        try server.send(ServerMessage.screen(text: "\u{1B}]52;c;screen-secret\u{07}"))
        do {
            try client.greetSessionProcess()
            Issue.record("A screen in place of hello was accepted.")
        } catch let error as SessionProtocolError {
            #expect(error == .unexpectedMessage(description: "screen arrived instead of hello"))
            #expect(!"\(error)".contains("screen-secret"), "error: \(error)")
            #expect(!"\(error)".contains("\u{1B}"), "error: \(error)")
        }
    }

    @Test func anUnexpectedFirstRequestIsNamedWithoutItsContents() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.sendText(identifier: UUID(), text: "typed-secret\u{1B}[31m"))
        do {
            try server.greetClient()
            Issue.record("A request in place of hello was accepted.")
        } catch let error as SessionProtocolError {
            #expect(error == .unexpectedMessage(description: "sendText arrived instead of hello"))
            #expect(!"\(error)".contains("typed-secret"), "error: \(error)")
            #expect(!"\(error)".contains("\u{1B}"), "error: \(error)")
        }
    }

    @Test func aControlFrameThatCannotBeParsedIsDescribedWithoutItsBytes() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        let payload = Array("\u{1B}]52;c;payload-secret\u{07}".utf8)
        let frame: [UInt8] = [0, 0, 0, UInt8(payload.count + 1), 1] + payload
        #expect(write(descriptors[0], frame, frame.count) == frame.count)
        do {
            _ = try receiver.receive(ServerMessage.self)
            Issue.record("Bytes that are not JSON were decoded.")
        } catch {
            #expect(!"\(error)".contains("\u{1B}"), "error: \(error)")
            #expect(!"\(error)".contains("payload-secret"), "error: \(error)")
        }
    }

    /// A request that could not be decoded closed the
    /// connection without a word. The first frame gets the failure too.
    @Test func aFirstFrameThatCannotBeDecodedGetsAFailureThatNamesTheProblem() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let client = MessageConnection(descriptor: descriptors[0])
        let server = MessageConnection(descriptor: descriptors[1])
        let payload = Array(#"{"hello":{"protocolVersion":"one"}}"#.utf8)
        let frame: [UInt8] = [0, 0, 0, UInt8(payload.count + 1), 1] + payload
        #expect(write(descriptors[0], frame, frame.count) == frame.count)
        #expect(throws: SessionProtocolError.malformedFrame(reason: "the field hello.protocolVersion has the wrong type")) {
            try server.greetClient()
        }
        server.shutdown()
        let answer = try client.receive(ServerMessage.self)
        #expect(answer == .failure(SessionFailure(
            reason: .invalidRequest,
            message: "A frame is malformed: the field hello.protocolVersion has the wrong type."
        )))
    }

    /// The session process closes a client's descriptor itself, to know when
    /// the socket is gone. The connection must not close the number again
    /// when it goes away: by then the system may have given it to another
    /// file.
    ///
    /// The tests of this product run side by side in one process, and they
    /// open and close descriptors all the time. The lowest free numbers
    /// belong to them, so this test works at a number near the top of the
    /// limit, which no other test meets. It proves the first close at the
    /// other end of the socket, because the number itself may be in use
    /// elsewhere.
    @Test func closeEndsTheDescriptorOnceAndLaterCallsFail() throws {
        try whileNoChildStarts { () throws in
            var limit = rlimit()
            #expect(getrlimit(RLIMIT_NOFILE, &limit) == 0)
            let reserved = Int32(min(limit.rlim_cur, 10_240)) - 8
            var descriptors: [Int32] = [0, 0]
            #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
            defer { close(descriptors[0]) }
            #expect(fcntl(descriptors[1], F_DUPFD, reserved) == reserved, "the reserved number is taken")
            close(descriptors[1])
            var connection: MessageConnection? = MessageConnection(descriptor: reserved)
            connection?.close()
            var byte: UInt8 = 0
            #expect(recv(descriptors[0], &byte, 1, MSG_DONTWAIT) == 0, "the other end of the socket is still open")
            #expect(throws: SessionProtocolError.self) { try connection?.send(ClientMessage.listSessions) }
            #expect(try connection?.receive(ClientMessage.self) == nil)
            connection?.close()

            // A file that takes the freed number must survive the connection.
            var pipeDescriptors: [Int32] = [0, 0]
            #expect(pipe(&pipeDescriptors) == 0)
            defer { close(pipeDescriptors[1]) }
            #expect(fcntl(pipeDescriptors[0], F_DUPFD, reserved) == reserved, "the freed number is taken")
            close(pipeDescriptors[0])
            defer { close(reserved) }
            var before = stat()
            #expect(fstat(reserved, &before) == 0)
            connection = nil
            var after = stat()
            #expect(fstat(reserved, &after) == 0, "the connection closed a descriptor it no longer owned")
            #expect(before.st_dev == after.st_dev && before.st_ino == after.st_ino, "another file holds the number now")
        }
    }

    /// macOS reports a peer that shut down only its sending side while
    /// bytes still wait, so a
    /// client that half-closes counts as gone, as a client that closes
    /// between two frames does. Its other direction still works.
    @Test func aPeerThatHalfClosedIsNoticedWhileItsBytesWait() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let server = MessageConnection(descriptor: descriptors[1])
        let waiting = [UInt8](repeating: 7, count: 4096)
        #expect(write(descriptors[0], waiting, waiting.count) == waiting.count)
        #expect(!server.peerHasClosed)
        #expect(shutdown(descriptors[0], SHUT_WR) == 0)
        #expect(server.peerHasClosed)
        try server.send(ServerMessage.acknowledged)
    }

    @Test func aHelloThatDoesNotArriveInTimeEndsTheGreeting() throws {
        let (client, server) = try MessageConnection.makePair()
        _ = client
        let start = ContinuousClock.now
        #expect(throws: SessionProtocolError.timedOut(waitingFor: "the rest of a frame")) {
            try server.greetClient(within: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aWriteThatMakesNoProgressEndsAfterTheStallLimit() throws {
        let (client, server) = try MessageConnection.makePair()
        _ = server
        // Nobody reads, so the socket fills up and the write stalls.
        let start = ContinuousClock.now
        #expect(throws: SessionProtocolError.timedOut(waitingFor: "the other side to take a frame")) {
            try client.send(ServerMessage.output(Data(count: 1024 * 1024)), stallLimit: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aPeerThatClosedIsNoticedWhileItsBytesWait() throws {
        let (client, server) = try MessageConnection.makePair()
        #expect(!server.peerHasClosed)
        try client.send(ClientMessage.input(Data(count: 4096)))
        #expect(!server.peerHasClosed)
        client.shutdown()
        #expect(server.peerHasClosed)
    }

    @Test func aRefusalIsReadEvenWhenTheHelloCannotGoOut() throws {
        let (client, server) = try MessageConnection.makePair()
        try server.send(ServerMessage.failure(SessionFailure(reason: .invalidRequest, message: "The session process already serves 64 clients.")))
        server.shutdown()
        #expect(throws: SessionProtocolError.refused(message: "The session process already serves 64 clients.")) {
            try client.greetSessionProcess()
        }
    }

    @Test func theVersionIsReadFromARefusal() {
        #expect(MessageConnection.version(inRefusal: MessageConnection.versionRefusal(ours: 12, theirs: 1)) == 12)
        #expect(MessageConnection.version(inRefusal: "Another text.") == nil)
    }

    @Test func connectingToAnAbsentSocketFailsWithAnErrorNumber() throws {
        let path = NSTemporaryDirectory() + "absent-\(UInt32.random(in: 0...UInt32.max)).socket"
        do {
            _ = try MessageConnection.connect(to: SocketLocation(path: path))
            Issue.record("The connection should have failed.")
        } catch let error as SessionProtocolError {
            #expect(error == .systemCallFailed(function: "connect", code: ENOENT))
        }
    }
}
