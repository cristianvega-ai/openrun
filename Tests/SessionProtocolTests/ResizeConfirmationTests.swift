import Foundation
import SessionProtocol
import Testing

@Suite struct ResizeConfirmationTests {
    private enum OlderServerMessage: Codable, Equatable {
        case hello(protocolVersion: Int)
    }
    private enum OlderClientMessage: Codable, Equatable {
        case resize(SessionSize)
    }
    private enum OlderSizeMessage: Codable, Equatable {
        case sizeChanged(SessionSize)
    }

    @Test func anOlderGreetingHasNoConfirmationCapability() throws {
        let (client, server) = try MessageConnection.makePair()
        try server.send(ServerMessage.hello(protocolVersion: MessageFrame.protocolVersion))
        #expect(try client.greetSessionProcess().orderedResizeConfirmation == false)
    }

    @Test func aGreetingWithTheCapabilityRemainsReadableByAnOlderClient() throws {
        let capabilities = ServerCapabilities(orderedResizeConfirmation: true)
        let message = ServerMessage.hello(protocolVersion: 1, capabilities: capabilities)
        let frame = try message.frame()
        #expect(try JSONDecoder().decode(OlderServerMessage.self, from: frame.payload) == .hello(protocolVersion: 1))
        #expect(try ServerMessage(frame: frame) == message)
        let (client, server) = try MessageConnection.makePair()
        try server.send(message)
        #expect(try client.greetSessionProcess() == capabilities)
    }

    @Test func aMissingCapabilityFieldDefaultsToFalse() throws {
        let frame = MessageFrame(kind: .control, payload: Data(#"{"hello":{"protocolVersion":1,"capabilities":{}}}"#.utf8))
        #expect(try ServerMessage(frame: frame) == .hello(protocolVersion: 1, capabilities: ServerCapabilities()))
        let legacy = MessageFrame(kind: .control, payload: Data(#"{"hello":{"protocolVersion":1}}"#.utf8))
        #expect(try ServerMessage(frame: legacy) == .hello(protocolVersion: 1))
    }

    @Test func aResizeRequestRemainsReadableByAnOlderServer() throws {
        let size = SessionSize(columns: 90, rows: 25)
        let message = ClientMessage.resize(size, requestsConfirmation: true)
        let frame = try message.frame()
        #expect(try JSONDecoder().decode(OlderClientMessage.self, from: frame.payload) == .resize(size))
        #expect(try ClientMessage(frame: frame) == message)
        let legacy = MessageFrame(kind: .control, payload: Data(#"{"resize":{"_0":{"columns":90,"rows":25}}}"#.utf8))
        #expect(try ClientMessage(frame: legacy) == .resize(size))
    }

    @Test func aSizeChangeAtALineStartRemainsReadableByAnOlderClient() throws {
        let size = SessionSize(columns: 90, rows: 25)
        let message = ServerMessage.sizeChanged(size, keepsCursorAtLineStart: true)
        let frame = try message.frame()
        #expect(try JSONDecoder().decode(OlderSizeMessage.self, from: frame.payload) == .sizeChanged(size))
        #expect(try ServerMessage(frame: frame) == message)
        #expect(try ServerMessage.sizeChanged(size).frame().payload == Data(#"{"sizeChanged":{"_0":{"columns":90,"rows":25}}}"#.utf8))
    }
}
