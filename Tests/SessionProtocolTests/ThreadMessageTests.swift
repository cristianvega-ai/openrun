import Foundation
import Testing
@testable import SessionProtocol

@Suite struct ThreadMessageTests {
    /// The texts are written by hand, so a change of the wire format fails here.
    @Test func eachMessageHasTheTextOfTheDocument() throws {
        let identifier = try #require(UUID(uuidString: "5F2A0000-0000-4000-8000-000000000001"))
        let name = #""5F2A0000-0000-4000-8000-000000000001""#
        let expected: [(any FramedMessage, String)] = [
            (ClientMessage.createThread(agent: "claude-code", folder: "/work/app"), #"{"createThread":{"agent":"claude-code","folder":"\/work\/app"}}"#),
            (ClientMessage.createThread(agent: "claude-code", folder: "/w", model: "opus", permissionMode: "plan", name: "Notes"),
             #"{"createThread":{"agent":"claude-code","folder":"\/w","model":"opus","name":"Notes","permissionMode":"plan"}}"#),
            (ClientMessage.listThreads, #"{"listThreads":{}}"#),
            (ClientMessage.renameThread(identifier: identifier, name: nil), #"{"renameThread":{"identifier":\#(name)}}"#),
            (ClientMessage.closeThread(identifier: identifier), #"{"closeThread":{"identifier":\#(name)}}"#),
            (ClientMessage.attachThread(identifier: identifier), #"{"attachThread":{"identifier":\#(name)}}"#),
            (ClientMessage.sendThreadMessage(identifier: identifier, text: "Go on."), #"{"sendThreadMessage":{"identifier":\#(name),"text":"Go on."}}"#),
            (ClientMessage.stopThread(identifier: identifier), #"{"stopThread":{"identifier":\#(name)}}"#),
            (ServerMessage.threadReplayComplete(hasEarlierEvents: true), #"{"threadReplayComplete":{"hasEarlierEvents":true}}"#),
            (ServerMessage.threadMessageSent(identifier: identifier), #"{"threadMessageSent":{"identifier":\#(name)}}"#),
            (ServerMessage.threadEnded(identifier: identifier), #"{"threadEnded":{"identifier":\#(name)}}"#),
            (ServerMessage.threadList([]), #"{"threadList":{"_0":[]}}"#),
        ]
        for (message, text) in expected {
            #expect(String(decoding: try message.frame().payload, as: UTF8.self) == text)
            if let client = message as? ClientMessage { #expect(try ClientMessage(frame: client.frame()) == client) }
            if let server = message as? ServerMessage { #expect(try ServerMessage(frame: server.frame()) == server) }
        }
        #expect(ClientMessage.sendThreadMessage(identifier: identifier, text: "secret").name == "sendThreadMessage")
    }

    @Test func theMessagesWithASummarySurviveTheWireAndAnOlderHelloHasNoThreads() throws {
        let summary = ThreadSummary(identifier: UUID(), agent: "claude-code", folder: "/work", model: "opus", permissionMode: "default",
                                    createdAt: Date(timeIntervalSince1970: 0), lastActivityAt: Date(timeIntervalSince1970: 0))
        for message in [ServerMessage.threadCreated(summary), .threadAttached(summary), .threadChanged(summary), .threadList([summary])] {
            #expect(try ServerMessage(frame: message.frame()) == message)
        }
        let older = try JSONDecoder.messages.decode(ServerCapabilities.self, from: Data(#"{"sessionChanges":true}"#.utf8))
        #expect(!older.threads && ServerCapabilities(threads: true).threads)
    }
}
