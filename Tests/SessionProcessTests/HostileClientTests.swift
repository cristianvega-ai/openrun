import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing

/// One frame as it travelled on the socket.
private struct ReceivedFrame {
    var kind: UInt8
    var payload: [UInt8]

    /// The JSON object of a control frame, or `nil`.
    var object: [String: Any]? {
        guard kind == 1 else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(payload))) as? [String: Any]
    }

    /// The name of the control message, which is the only key of its object.
    var messageName: String? { object?.keys.first }

    /// The fields of a control message.
    var fields: [String: Any]? { messageName.flatMap { object?[$0] as? [String: Any] } }
}

/// A client that writes bytes to the socket by hand, without the protocol
/// code of the product. The frames are built from numbers written out here, so
/// a client that breaks the rules can be as wrong as a test wants.
private final class HostileClient: Sendable {
    private let descriptor: Int32

    init(socketPath: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        // Set before connecting. Once the other side has closed, the system
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
            throw HarnessError.commandFailed(description: "connect failed: \(String(cString: strerror(code)))")
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    /// A frame from its parts: four bytes of length, which counts the kind
    /// and the payload, then the kind, then the payload.
    static func frame(kind: UInt8, payload: [UInt8]) -> [UInt8] {
        let length = UInt32(payload.count + 1)
        return [UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF), kind] + payload
    }

    /// A control frame from the text of its message.
    static func control(_ text: String) -> [UInt8] {
        frame(kind: 1, payload: Array(text.utf8))
    }

    static let hello = control(#"{"hello":{"protocolVersion":1}}"#)

    /// Writes the bytes. Returns whether they all went out.
    @discardableResult
    func send(_ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let count = bytes[offset...].withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                offset += count
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// Reads up to `count` bytes, or fewer when the connection ends or the
    /// time passes. `closed` says whether the end came from the other side.
    private func read(count: Int, deadline: ContinuousClock.Instant) -> (bytes: [UInt8], closed: Bool) {
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while bytes.count < count {
            let remaining = deadline - .now
            guard remaining > .zero else { return (bytes, false) }
            var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(clamping: remaining.components.seconds * 1000 + remaining.components.attoseconds / 1_000_000_000_000_000)
            let ready = poll(&entry, 1, max(1, milliseconds))
            if ready < 0 && errno == EINTR { continue }
            if ready <= 0 { continue }
            let received = Darwin.read(descriptor, &buffer, min(buffer.count, count - bytes.count))
            if received > 0 {
                bytes += buffer[..<received]
            } else if received == 0 || (errno != EINTR && errno != EAGAIN) {
                return (bytes, true)
            }
        }
        return (bytes, false)
    }

    /// The next whole frame. `nil` when the other side closed the connection
    /// or the time passed first.
    func receiveFrame(within limit: Duration = .seconds(15)) -> ReceivedFrame? {
        let deadline = ContinuousClock.now + limit
        let field = read(count: 4, deadline: deadline)
        guard field.bytes.count == 4 else { return nil }
        let length = field.bytes.reduce(0) { $0 << 8 | Int($1) }
        guard length >= 1, length <= 64 * 1024 * 1024 + 1 else { return nil }
        let body = read(count: length, deadline: deadline)
        guard body.bytes.count == length else { return nil }
        return ReceivedFrame(kind: body.bytes[0], payload: Array(body.bytes.dropFirst()))
    }

    /// Reads and drops everything until the other side closes the connection.
    /// Returns whether it closed before the time passed.
    func waitForClose(within limit: Duration = .seconds(15)) -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            let result = read(count: 64 * 1024, deadline: deadline)
            if result.closed { return true }
        }
        return false
    }

    /// Says hello and checks the answer.
    func greet() throws {
        send(Self.hello)
        let answer = receiveFrame()
        guard answer?.messageName == "hello" else {
            throw HarnessError.commandFailed(description: "The answer to hello was \(String(describing: answer?.messageName)).")
        }
    }
}

/// A client that stays attached to a session that prints a numbered line every
/// 100 milliseconds. It is the neighbor that a hostile client must not harm:
/// the numbers keep growing only while its connection and its session work.
private final class Neighbor: Sendable {
    private let connection: MessageConnection
    private let text = Mutex("")

    init(socketPath: String, identifier: String) throws {
        connection = try MessageConnection.connect(to: SocketLocation(path: socketPath))
        try connection.greetSessionProcess()
        try connection.send(ClientMessage.attach(identifier: UUID(uuidString: identifier)!, size: SessionSize(columns: 80, rows: 24)))
        guard case .attached = try connection.receive(ServerMessage.self),
              case .snapshot = try connection.receive(ServerMessage.self)
        else {
            throw HarnessError.commandFailed(description: "The neighbor could not attach.")
        }
    }

    /// The highest number printed so far among the lines it has seen.
    var latestTick: Int {
        text.withLock { text in
            text.components(separatedBy: CharacterSet.newlines)
                .compactMap { $0.hasPrefix("tick-") ? Int($0.dropFirst(5)) : nil }
                .max() ?? 0
        }
    }

    /// Reads until a line with a number above `tick` has arrived. Returns
    /// `false` when the connection ends or the time passes first.
    func waitForTick(above tick: Int, within limit: TimeInterval = 20) -> Bool {
        let watchdog = DispatchWorkItem { [connection] in connection.shutdown() }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
        defer { watchdog.cancel() }
        while latestTick <= tick {
            guard let message = try? connection.receive(ServerMessage.self) else { return false }
            switch message {
            case .output(let bytes): text.withLock { $0 += String(decoding: bytes, as: UTF8.self) }
            case .exited: return false
            default: continue
            }
        }
        return true
    }

    func close() {
        connection.shutdown()
    }
}

/// A server with one session and one neighbor attached to it.
private func withNeighbor(_ body: (RunningSessionProcess, String, Neighbor) async throws -> Void) async throws {
    try await RunningSessionProcess.run { process in
        let identifier = try process.createSession(program: ["/bin/sh", "-c", "number=0; while :; do number=$((number+1)); echo tick-$number; sleep 0.1; done"])
        #expect(await process.waitForScreen(of: identifier, containing: "tick-2"))
        let neighbor = try Neighbor(socketPath: process.socketPath, identifier: identifier)
        defer { neighbor.close() }
        #expect(neighbor.waitForTick(above: 1), "the neighbor got no output before the test began")
        try await body(process, identifier, neighbor)
    }
}

/// Checks that the server serves everyone else: the process runs, the session
/// is listed, a new client can start a session and read it, and the neighbor
/// that was attached all along still gets new output.
private func expectTheServerKeepsServing(
    _ process: RunningSessionProcess,
    identifier: String,
    alsoListed others: [String] = [],
    neighbor: Neighbor,
    _ context: Comment
) async throws {
    #expect(process.isRunning, context)
    #expect(Set(try process.listedIdentifiers()) == Set([identifier] + others), context)
    let extra = try process.createSession(program: ["/bin/sh", "-c", "echo extra-session-works; sleep 60"])
    #expect(await process.waitForScreen(of: extra, containing: "extra-session-works"), context)
    #expect(try process.runCommand(["kill", extra]).status == 0, context)
    let before = neighbor.latestTick
    #expect(neighbor.waitForTick(above: before + 2), "the neighbor stopped getting output after the \(context)")
}

/// The ways a client can break the rules so that the server must end its
/// connection.
enum Offense: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case lengthZero
    case unknownKind
    case kindZero
    case textThatIsNotStructured
    case unknownMessage
    case badIdentifier
    case outputFrameFromAClient
    case snapshotFrameFromAClient
    case serverMessageFromAClient
    case keysInsideATextFrame
    case lengthAboveTheLimit
    case lengthOfFourBillionBytes
    case requestBeforeHello
    case webRequestInsteadOfHello
    case oversizedLengthAfterAGoodRequest

    var testDescription: String { rawValue }

    /// Whether the client says hello before the offense.
    var greetsFirst: Bool {
        switch self {
        case .requestBeforeHello, .webRequestInsteadOfHello: false
        default: true
        }
    }

    var bytes: [UInt8] {
        switch self {
        case .lengthZero: [0, 0, 0, 0]
        case .unknownKind: HostileClient.frame(kind: 99, payload: Array("{}".utf8))
        case .kindZero: HostileClient.frame(kind: 0, payload: Array("{}".utf8))
        case .textThatIsNotStructured: HostileClient.control("this is not json")
        case .unknownMessage: HostileClient.control(#"{"noSuchMessage":{}}"#)
        case .badIdentifier:
            HostileClient.control(#"{"readScreen":{"identifier":"not-an-identifier","includeScrollback":false}}"#)
        case .outputFrameFromAClient: HostileClient.frame(kind: 2, payload: Array("output".utf8))
        case .snapshotFrameFromAClient: HostileClient.frame(kind: 4, payload: Array("snapshot".utf8))
        case .serverMessageFromAClient: HostileClient.control(#"{"acknowledged":{}}"#)
        case .keysInsideATextFrame: HostileClient.control(#"{"input":{"_0":"\#(Data([1]).base64EncodedString())"}}"#)
        // 64 MiB and two more bytes: one above the largest payload.
        case .lengthAboveTheLimit: [0x04, 0x00, 0x00, 0x02]
        case .lengthOfFourBillionBytes: [0xFF, 0xFF, 0xFF, 0xFF]
        case .requestBeforeHello: HostileClient.control(#"{"listSessions":{}}"#)
        // The first four bytes, "GET ", read as a length of about 1.2 GB.
        case .webRequestInsteadOfHello: Array("GET / HTTP/1.0\r\n\r\n".utf8)
        case .oversizedLengthAfterAGoodRequest: HostileClient.control(#"{"listSessions":{}}"#) + [0x04, 0x00, 0x00, 0x02]
        }
    }
}

/// Control frames that the server cannot decode. Each one gets a failure that
/// names the problem, and then the connection closes.
enum UnreadableRequest: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case textThatIsNotStructured
    case keysInsideATextFrame
    case columnsAboveTheLargestSize
    case rowsBelowZero
    case unknownMessage
    case badIdentifier
    case deeplyNestedText

    var testDescription: String { rawValue }

    var bytes: [UInt8] {
        switch self {
        case .textThatIsNotStructured: HostileClient.control("\u{1B}]52;c;this is not json\u{07}")
        case .keysInsideATextFrame: HostileClient.control(#"{"input":{"_0":"\#(Data([1]).base64EncodedString())"}}"#)
        case .columnsAboveTheLargestSize:
            HostileClient.control(#"{"createSession":{"folder":"/","size":{"columns":999999,"rows":24},"environment":{}}}"#)
        case .rowsBelowZero: HostileClient.control(#"{"resize":{"_0":{"columns":80,"rows":-1}}}"#)
        case .unknownMessage: HostileClient.control(#"{"noSuchMessage\u001b[31m":{}}"#)
        case .badIdentifier:
            HostileClient.control(#"{"readScreen":{"identifier":"not-an-identifier\u001b[2J","includeScrollback":false}}"#)
        // A mebibyte of nested arrays.
        case .deeplyNestedText: HostileClient.frame(kind: 1, payload: [UInt8](repeating: UInt8(ascii: "["), count: 1024 * 1024))
        }
    }

    /// Words that the failure must hold, so that it names the problem.
    var expectedWords: String {
        switch self {
        case .textThatIsNotStructured: "not valid JSON"
        case .keysInsideATextFrame: "input must be a raw frame"
        case .columnsAboveTheLargestSize: "createSession.size.columns"
        case .rowsBelowZero: "resize._0.rows"
        case .unknownMessage: "the name of one message"
        case .badIdentifier: "readScreen.identifier"
        case .deeplyNestedText: "nests too deeply"
        }
    }
}

/// Reads frames until a control frame arrives, and returns it. Output that a
/// session sends to an attached client may come first.
private func nextControlFrame(from client: HostileClient) -> ReceivedFrame? {
    while let frame = client.receiveFrame() {
        if frame.kind == 1 { return frame }
    }
    return nil
}

/// Checks that a frame is a failure with reason `invalidRequest` whose
/// message holds the words and no control character of the request.
private func expectUnreadableRequestFailure(_ frame: ReceivedFrame?, naming words: String, _ context: Comment) {
    #expect(frame?.messageName == "failure", "the answer was \(String(describing: frame?.messageName)) after \(context)")
    let failure = frame?.fields?["_0"] as? [String: Any]
    #expect(failure?["reason"] as? String == "invalidRequest", "reason: \(String(describing: failure?["reason"])) after \(context)")
    let message = failure?["message"] as? String ?? ""
    #expect(message.contains(words), "message: \(message)")
    #expect(!message.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }, "the message holds a control character: \(message.debugDescription)")
}

extension SessionProcessIntegration {
    /// Clients that break the rules, against a running server. Each one ends
    /// its own connection, or gets an answer on it, and nothing else changes:
    /// the server runs, and a neighbor that is attached to a session keeps
    /// getting its output.
    @Suite struct HostileClientTests {
        @Test(arguments: Offense.allCases)
        func aClientThatBreaksTheRulesLosesItsConnectionAndNobodyElseNotices(offense: Offense) async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                if offense.greetsFirst { try hostile.greet() }
                hostile.send(offense.bytes)

                #expect(hostile.waitForClose(), "the server did not end the connection after \(offense.rawValue)")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "\(offense.rawValue)")
            }
        }

        /// A request that could not be decoded ended the
        /// connection without a word.
        @Test(arguments: UnreadableRequest.allCases)
        func aRequestThatCannotBeReadGetsAFailureThatNamesTheProblemBeforeTheClose(request: UnreadableRequest) async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                try hostile.greet()
                hostile.send(request.bytes)

                expectUnreadableRequestFailure(hostile.receiveFrame(), naming: request.expectedWords, "\(request.rawValue)")
                #expect(hostile.waitForClose(), "the server did not end the connection after \(request.rawValue)")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "\(request.rawValue)")
            }
        }

        @Test func aFirstFrameThatCannotBeReadGetsAFailureInPlaceOfHello() async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                hostile.send(HostileClient.control(#"{"hello":{"protocolVersion":"one"}}"#))

                expectUnreadableRequestFailure(hostile.receiveFrame(), naming: "hello.protocolVersion", "a hello that cannot be read")
                #expect(hostile.waitForClose(), "the server did not end the connection")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "a hello that cannot be read")
            }
        }

        @Test func anAttachedClientThatSendsARequestThatCannotBeReadIsAnsweredAndDetached() async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                try hostile.greet()
                hostile.send(HostileClient.control(#"{"attach":{"identifier":"\#(identifier.uppercased())","size":{"columns":80,"rows":24}}}"#))
                let attached = nextControlFrame(from: hostile)
                #expect(attached?.messageName == "attached", "the attach was answered with \(String(describing: attached?.messageName))")
                hostile.send(UnreadableRequest.rowsBelowZero.bytes)

                expectUnreadableRequestFailure(nextControlFrame(from: hostile), naming: UnreadableRequest.rowsBelowZero.expectedWords, "a resize that cannot be read")
                #expect(hostile.waitForClose(), "the server did not end the connection")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "an attached client with a resize that cannot be read")
            }
        }

        /// A frame of deeply nested JSON, as large as a frame may be, must not
        /// crash the session process or exhaust the stack of the thread that
        /// reads the client.
        @Test func aDeeplyNestedRequestOfTheLargestFrameSizeIsAnsweredAndNobodyElseNotices() async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                try hostile.greet()
                let largest = 64 * 1024 * 1024
                #expect(hostile.send(HostileClient.frame(kind: 1, payload: [UInt8](repeating: UInt8(ascii: "["), count: largest))))

                expectUnreadableRequestFailure(hostile.receiveFrame(within: .seconds(30)), naming: "nests too deeply", "64 MiB of nested arrays")
                #expect(hostile.waitForClose(), "the server did not end the connection")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "64 MiB of nested arrays")
            }
        }

        @Test func aClientWithAnotherProtocolVersionIsToldAndEnded() async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                hostile.send(HostileClient.control(#"{"hello":{"protocolVersion":99}}"#))

                let answer = try #require(hostile.receiveFrame())
                #expect(answer.messageName == "failure")
                let failure = answer.fields?["_0"] as? [String: Any]
                #expect(failure?["reason"] as? String == "incompatibleProtocol")
                #expect((failure?["message"] as? String)?.contains("protocol version 1") == true, "message: \(String(describing: failure?["message"]))")
                #expect(hostile.waitForClose(), "the server did not end the connection")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "wrong version")
            }
        }

        @Test func aSecondHelloIsAnsweredWithAFailureAndTheConnectionStaysUsable() async throws {
            try await withNeighbor { process, identifier, neighbor in
                let hostile = try HostileClient(socketPath: process.socketPath)
                try hostile.greet()
                hostile.send(HostileClient.hello)

                let answer = try #require(hostile.receiveFrame())
                #expect(answer.messageName == "failure")
                let failure = answer.fields?["_0"] as? [String: Any]
                #expect(failure?["reason"] as? String == "invalidRequest")

                // The mistake costs the client nothing more than the answer.
                hostile.send(HostileClient.control(#"{"listSessions":{}}"#))
                let list = try #require(hostile.receiveFrame())
                #expect(list.messageName == "sessionList")
                #expect((list.fields?["_0"] as? [Any])?.count == 1)
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "second hello")
            }
        }

        @Test func aClientThatSaysNothingIsEndedAtTheHelloDeadlineAndBlocksNoOne() async throws {
            try await withNeighbor { process, identifier, neighbor in
                let silent = try HostileClient(socketPath: process.socketPath)
                let start = ContinuousClock.now
                // While it keeps the connection open, everyone else is served.
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "silent client, while it waits")

                #expect(silent.waitForClose(within: .seconds(20)), "the server never ended the silent connection")
                let waited = ContinuousClock.now - start
                // The server allows five seconds for the hello. It does not
                // end a connection at once, and it does not wait for ever.
                #expect(waited > .seconds(3), "the connection ended after \(waited)")
                try await expectTheServerKeepsServing(process, identifier: identifier, neighbor: neighbor, "silent client, after it was ended")
            }
        }
    }
}
