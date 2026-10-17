import Foundation
import Synchronization
import Testing
@testable import SessionProtocol

@Suite struct MessageFrameTests {
    @Test func aFrameStartsWithLengthThenKindThenPayload() throws {
        let frame = MessageFrame(kind: .output, payload: Data([0x68, 0x69]))
        #expect(try frame.encoded() == Data([0, 0, 0, 3, 2, 0x68, 0x69]))
    }


    @Test func anEmptyPayloadIsAllowed() throws {
        let frame = MessageFrame(kind: .input, payload: Data())
        #expect(try frame.encoded() == Data([0, 0, 0, 1, 3]))
    }
}
