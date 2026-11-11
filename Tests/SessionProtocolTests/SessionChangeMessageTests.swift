import Foundation
import Testing
@testable import SessionProtocol

@Suite struct SessionChangeMessageTests {
    private static let identifierText = "3F2A9C1E-0000-4000-8000-000000000001"
    private static let identifier = UUID(uuidString: identifierText)!

    @Test func eachMessageHasTheTextOfTheDocument() throws {
        let summary = SessionSummary(identifier: Self.identifier, folder: "work", command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 0))
        let summaryText = #"{"command":["sh"],"createdAt":0,"folder":"work","identifier":"\#(Self.identifierText)","size":{"columns":80,"rows":24}}"#
        let expected: [(any FramedMessage, String)] = [
            (ClientMessage.receiveSessionChanges(), #"{"receiveSessionChanges":{}}"#),
            (ClientMessage.receiveSessionChanges(includesThreads: true), #"{"receiveSessionChanges":{"includesThreads":true}}"#),
            (ClientMessage.renameSession(identifier: Self.identifier, name: "build"), #"{"renameSession":{"identifier":"\#(Self.identifierText)","name":"build"}}"#),
            (ClientMessage.renameSession(identifier: Self.identifier, name: nil), #"{"renameSession":{"identifier":"\#(Self.identifierText)"}}"#),
            (ClientMessage.raiseSessionAlert(identifier: Self.identifier, text: "done"), #"{"raiseSessionAlert":{"identifier":"\#(Self.identifierText)","text":"done"}}"#),
            (ClientMessage.clearSessionAlert(identifier: Self.identifier), #"{"clearSessionAlert":{"identifier":"\#(Self.identifierText)"}}"#),
            (ServerMessage.sessionChanged(summary), #"{"sessionChanged":{"_0":\#(summaryText)}}"#),
            (ServerMessage.sessionEnded(identifier: Self.identifier), #"{"sessionEnded":{"identifier":"\#(Self.identifierText)"}}"#),
        ]
        for (message, text) in expected {
            #expect(String(decoding: try message.frame().payload, as: UTF8.self) == text)
        }
        for (message, _) in expected {
            if let client = message as? ClientMessage { #expect(try ClientMessage(frame: client.frame()) == client) }
            if let server = message as? ServerMessage { #expect(try ServerMessage(frame: server.frame()) == server) }
        }
    }

    @Test func theCapabilityIsOffWhenTheFieldIsMissing() throws {
        let older = MessageFrame(kind: .control, payload: Data(#"{"hello":{"capabilities":{"orderedResizeConfirmation":true},"protocolVersion":1}}"#.utf8))
        #expect(try ServerMessage(frame: older) == .hello(protocolVersion: 1, capabilities: ServerCapabilities(orderedResizeConfirmation: true)))
        let capabilities = ServerCapabilities(orderedResizeConfirmation: true, sessionChanges: true)
        let (client, server) = try MessageConnection.makePair()
        defer { client.shutdown(); server.shutdown() }
        try server.send(ServerMessage.hello(protocolVersion: 1, capabilities: capabilities))
        #expect(try client.greetSessionProcess() == capabilities)
    }
}
