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

    @Test func theSummaryOfAThreadHasEachFactAndAnImageTravelsAsBase64() throws {
        let identifier = try #require(UUID(uuidString: "5F2A0000-0000-4000-8000-000000000001"))
        var summary = ThreadSummary(identifier: identifier, agent: "claude-code", folder: "/work/app", model: "opus", permissionMode: "default",
                                    createdAt: Date(timeIntervalSince1970: 0), lastActivityAt: Date(timeIntervalSince1970: 60))
        (summary.title, summary.state, summary.waitingMessageCount) = ("Repair the resize", "inProgress", 1)
        let text = String(decoding: try JSONEncoder.messages.encode(summary), as: UTF8.self)
        #expect(text.contains(#""agent":"claude-code""#) && text.contains(#""state":"inProgress""#) && text.contains(#""isProcessRunning":false"#))
        #expect(try JSONDecoder.messages.decode(ThreadSummary.self, from: Data(text.utf8)) == summary)
        #expect(summary.identifierText == "5f2a0000-0000-4000-8000-000000000001")
        let image = ThreadImage(mediaType: "image/png", data: Data([1, 2, 3]))
        let imageText = String(decoding: try JSONEncoder.messages.encode(image), as: UTF8.self)
        #expect(imageText.contains(#""data":"AQID""#) && imageText.contains(#""mediaType":"image\/png""#) || imageText.contains(#""mediaType":"image/png""#))
        #expect(try JSONDecoder.messages.decode(ThreadImage.self, from: Data(imageText.utf8)) == image)
    }
}
