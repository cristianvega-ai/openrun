import Foundation
import Synchronization
import Testing
@testable import SessionProtocol

@Suite struct MessageFrameTests {
    @Test func aFrameStartsWithLengthThenKindThenPayload() throws {
        let frame = MessageFrame(kind: .output, payload: Data([0x68, 0x69]))
        #expect(try frame.encoded() == Data([0, 0, 0, 3, 2, 0x68, 0x69]))
    }

    @Test func aFrameSurvivesEncodingAndDecoding() throws {
        let frame = MessageFrame(kind: .snapshot, payload: Data((0...255).map { UInt8($0) }))
        let bytes = try frame.encoded()
        let length = try MessageFrame.bodyLength(fromLengthField: bytes.prefix(4))
        #expect(length == bytes.count - 4)
        #expect(try MessageFrame(body: bytes.dropFirst(4)) == frame)
    }

    @Test func anEmptyPayloadIsAllowed() throws {
        let frame = MessageFrame(kind: .input, payload: Data())
        #expect(try frame.encoded() == Data([0, 0, 0, 1, 3]))
    }

    @Test func aLengthAboveTheLimitIsRejectedBeforeAnyReading() {
        let tooLarge = UInt32(MessageFrame.maximumPayloadLength + 2).bigEndian
        let field = withUnsafeBytes(of: tooLarge) { Data($0) }
        #expect(throws: SessionProtocolError.frameTooLarge(length: MessageFrame.maximumPayloadLength + 1, limit: MessageFrame.maximumPayloadLength)) {
            try MessageFrame.bodyLength(fromLengthField: field)
        }
    }

    @Test func theLargestPayloadIsAccepted() throws {
        let largest = UInt32(MessageFrame.maximumPayloadLength + 1).bigEndian
        let field = withUnsafeBytes(of: largest) { Data($0) }
        #expect(try MessageFrame.bodyLength(fromLengthField: field) == MessageFrame.maximumPayloadLength + 1)
    }

    @Test func aZeroLengthIsMalformed() {
        #expect(throws: SessionProtocolError.self) {
            try MessageFrame.bodyLength(fromLengthField: Data([0, 0, 0, 0]))
        }
    }

    @Test func anUnknownKindIsMalformed() {
        #expect(throws: SessionProtocolError.self) { try MessageFrame(body: Data([99, 1, 2])) }
        #expect(throws: SessionProtocolError.self) { try MessageFrame(body: Data()) }
    }

    @Test func encodingRefusesAPayloadAboveTheLimit() {
        let frame = MessageFrame(kind: .output, payload: Data(count: MessageFrame.maximumPayloadLength + 1))
        #expect(throws: SessionProtocolError.self) { try frame.encoded() }
    }

    @Test func controlMessagesAreText() throws {
        let identifier = UUID()
        let frame = try ClientMessage.killSession(identifier: identifier).frame()
        #expect(frame.kind == .control)
        let text = String(decoding: frame.payload, as: UTF8.self)
        #expect(text.contains("killSession"))
        #expect(text.contains(identifier.uuidString))
    }

    @Test func terminalBytesAreRawFrames() throws {
        #expect(try ClientMessage.input(Data([1, 2])).frame() == MessageFrame(kind: .input, payload: Data([1, 2])))
        #expect(try ServerMessage.output(Data([3])).frame() == MessageFrame(kind: .output, payload: Data([3])))
        #expect(try ServerMessage.snapshot(Data([4])).frame() == MessageFrame(kind: .snapshot, payload: Data([4])))
    }

    @Test func everyMessageSurvivesEncodingAndDecoding() throws {
        let identifier = UUID()
        let size = SessionSize(columns: 80, rows: 24)
        let summary = SessionSummary(
            identifier: identifier,
            folder: "/work",
            command: ["/bin/zsh", "-l"],
            size: size,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let clientMessages: [ClientMessage] = [
            .hello(protocolVersion: 1),
            .createSession(folder: "/work", command: nil, size: size, environment: ["PATH": "/bin"]),
            .createSession(folder: "/work", command: ["ls", "-l"], size: size, environment: [:]),
            .listSessions,
            .readScreen(identifier: identifier, includeScrollback: true),
            .sendText(identifier: identifier, text: "echo \"quoted\" \u{1F600}"),
            .killSession(identifier: identifier),
            .attach(identifier: identifier, size: size),
            .attach(identifier: identifier, size: size, relaysRawOutput: false, receivesSizeChanges: true),
            .input(Data([0x1B, 0x5B, 0x41])),
            .resize(size),
            .detach,
        ]
        for message in clientMessages {
            #expect(try ClientMessage(frame: message.frame()) == message)
        }
        let serverMessages: [ServerMessage] = [
            .hello(protocolVersion: 1),
            .sessionCreated(summary),
            .sessionList([summary, summary]),
            .attached(summary),
            .snapshot(Data([1, 2, 3])),
            .output(Data([0xE2, 0x82])),
            .sizeChanged(SessionSize(columns: 100, rows: 30)),
            .screen(text: "line\nline"),
            .exited(.exited(status: 3)),
            .exited(.signaled(signal: 9)),
            .acknowledged,
            .failure(SessionFailure(reason: .unknownSession, message: "No session.")),
        ]
        for message in serverMessages {
            #expect(try ServerMessage(frame: message.frame()) == message)
        }
    }

    @Test func aFrameForTheOtherDirectionIsRefused() {
        #expect(throws: SessionProtocolError.self) {
            try ClientMessage(frame: MessageFrame(kind: .output, payload: Data()))
        }
        #expect(throws: SessionProtocolError.self) {
            try ServerMessage(frame: MessageFrame(kind: .input, payload: Data()))
        }
    }

    @Test func keysInsideATextFrameAreRefused() throws {
        let encodedMessage = try JSONEncoder().encode(ClientMessage.input(Data([1])))
        #expect(throws: SessionProtocolError.self) {
            try ClientMessage(frame: MessageFrame(kind: .control, payload: encodedMessage))
        }
    }

    @Test func garbageInAControlFrameThrows() {
        #expect(throws: (any Error).self) {
            try ServerMessage(frame: MessageFrame(kind: .control, payload: Data("not json".utf8)))
        }
    }

    /// A request that cannot be decoded gets a
    /// failure that names the problem. The reason uses the words of the
    /// protocol and never the bytes of the request, which can hold escape
    /// sequences.
    @Test(arguments: [
        ("\u{1B}]52;c;secret\u{07}", "the control message is not valid JSON, or nests too deeply"),
        (#"{"noSuchMessage":{}}"#, "the control message is not a JSON object with the name of one message of the protocol"),
        (#"{"resize":{"_0":{"columns":999999,"rows":24}}}"#, "the field resize._0.columns holds a value that is out of range or in the wrong form"),
        (#"{"resize":{"_0":{"columns":80,"rows":-1}}}"#, "the field resize._0.rows holds a value that is out of range or in the wrong form"),
        (#"{"hello":{"protocolVersion":1e300}}"#, "a value in the control message is out of range"),
        (#"{"attach":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001"}}"#, "the field attach.size is missing"),
        (#"{"readScreen":{"identifier":"\u001b[31mnot-an-identifier","includeScrollback":false}}"#, "the field readScreen.identifier holds a value that is out of range or in the wrong form"),
        (#"{"hello":{"protocolVersion":null}}"#, "the field hello.protocolVersion is null"),
        (#"{"createSession":{"folder":"/","size":{"columns":80,"rows":24},"environment":{"\u001b[31mNAME":5}}}"#, "the field createSession.environment.(a name) has the wrong type"),
        (#"{"input":{"_0":"\#(Data([1]).base64EncodedString())"}}"#, "input must be a raw frame"),
    ])
    func aRequestThatCannotBeDecodedIsDescribedInTheWordsOfTheProtocol(payload: String, reason: String) {
        #expect(throws: SessionProtocolError.malformedFrame(reason: reason)) {
            try ClientMessage(frame: MessageFrame(kind: .control, payload: Data(payload.utf8)))
        }
    }

    @Test func anAnswerThatCannotBeDecodedIsDescribedWithoutItsBytes() {
        #expect(throws: SessionProtocolError.malformedFrame(reason: "the control message is not valid JSON, or nests too deeply")) {
            try ServerMessage(frame: MessageFrame(kind: .control, payload: Data("\u{1B}[2J not json".utf8)))
        }
    }

    @Test func aSizeKeepsItsTextAndRefusesWhatDoesNotFit() throws {
        let encoded = try JSONEncoder.messages.encode(SessionSize(columns: 65535, rows: 0))
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"columns":65535,"rows":0}"#)
        #expect(try JSONDecoder.messages.decode(SessionSize.self, from: encoded) == SessionSize(columns: 65535, rows: 0))
        #expect(throws: DecodingError.self) {
            try JSONDecoder.messages.decode(SessionSize.self, from: Data(#"{"columns":65536,"rows":1}"#.utf8))
        }
    }

    @Test func exitStatusFollowsTheShellConvention() {
        #expect(SessionExit.exited(status: 4).shellStatus == 4)
        #expect(SessionExit.signaled(signal: 15).shellStatus == 143)
    }
}
