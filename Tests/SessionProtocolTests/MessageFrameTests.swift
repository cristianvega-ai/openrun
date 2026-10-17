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

    @Test func keysInsideATextFrameAreRefused() throws {
        let encodedMessage = try JSONEncoder().encode(ClientMessage.input(Data([1])))
        #expect(throws: SessionProtocolError.self) {
            try ClientMessage(frame: MessageFrame(kind: .control, payload: encodedMessage))
        }
    }

    @Test func exitStatusFollowsTheShellConvention() {
        #expect(SessionExit.exited(status: 4).shellStatus == 4)
        #expect(SessionExit.signaled(signal: 15).shellStatus == 143)
    }
}
