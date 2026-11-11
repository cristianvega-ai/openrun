import Foundation
import Testing
@testable import SessionProtocol

@Suite struct ThreadEventFrameTests {
    /// The bytes are written by hand, so a change of the wire format fails here.
    @Test func anEventOfAThreadIsARawFrameOfKindFive() throws {
        let event = Data(#"{"kind":{}}"#.utf8)
        let frame = try ServerMessage.threadEvent(event).frame()
        #expect(frame.kind.rawValue == 5 && frame.payload == event)
        #expect(try frame.encoded() == Data([0, 0, 0, 12, 5]) + event)
        #expect(try ServerMessage(frame: MessageFrame(body: Data([5]) + event)) == .threadEvent(event))
        #expect(ServerMessage.threadEvent(event).name == "threadEvent")
    }

    @Test func anEventInAControlFrameAndAnEventForTheServerAreRefused() throws {
        let control = MessageFrame(kind: .control, payload: Data(#"{"threadEvent":{"_0":"e30="}}"#.utf8))
        #expect(throws: SessionProtocolError.malformedFrame(reason: "an event of a thread must be a raw frame")) { try ServerMessage(frame: control) }
        #expect(throws: SessionProtocolError.unexpectedMessage(description: "a server frame arrived at the server")) {
            try ClientMessage(frame: MessageFrame(kind: .threadEvent, payload: Data()))
        }
    }
}
