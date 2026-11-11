import Foundation
import Testing
@testable import SessionProtocol

@Suite struct ProjectMessageTests {
    private static let identifierText = "3F2A9C1E-0000-4000-8000-000000000001"
    private static let identifier = UUID(uuidString: identifierText)!

    /// The encoder of the protocol writes each slash as `\/`.
    @Test func eachMessageHasTheTextOfTheDocument() throws {
        let project = ProjectSummary(identifier: Self.identifier, name: "App", folder: "/work/app")
        let projectText = #"{"folder":"\/work\/app","identifier":"\#(Self.identifierText)","name":"App"}"#
        let hidden = ProjectSummary(identifier: Self.identifier, name: nil, folder: nil)
        let expected: [(any FramedMessage, String)] = [
            (ClientMessage.listProjects, #"{"listProjects":{}}"#),
            (ClientMessage.addProject(folder: "app", name: "App", currentFolder: "/work"), #"{"addProject":{"currentFolder":"\/work","folder":"app","name":"App"}}"#),
            (ClientMessage.addProject(folder: "/work/app", name: nil, currentFolder: nil), #"{"addProject":{"folder":"\/work\/app"}}"#),
            (ClientMessage.removeProject(identifier: Self.identifier), #"{"removeProject":{"identifier":"\#(Self.identifierText)"}}"#),
            (ClientMessage.renameProject(identifier: Self.identifier, name: "App"), #"{"renameProject":{"identifier":"\#(Self.identifierText)","name":"App"}}"#),
            (ClientMessage.renameProject(identifier: Self.identifier, name: nil), #"{"renameProject":{"identifier":"\#(Self.identifierText)"}}"#),
            (ClientMessage.moveProject(identifier: Self.identifier, place: 0), #"{"moveProject":{"identifier":"\#(Self.identifierText)","place":0}}"#),
            (ServerMessage.projectList([project, hidden]), #"{"projectList":{"_0":[\#(projectText),{"identifier":"\#(Self.identifierText)"}]}}"#),
            (ServerMessage.projectAdded(project), #"{"projectAdded":{"_0":\#(projectText)}}"#),
        ]
        for (message, text) in expected {
            let actual = String(decoding: try message.frame().payload, as: UTF8.self)
            #expect(actual == text, "\(actual)")
            if let client = message as? ClientMessage { #expect(try ClientMessage(frame: client.frame()) == client) }
            if let server = message as? ServerMessage { #expect(try ServerMessage(frame: server.frame()) == server) }
        }
    }

    /// The project of a session is one more fact, absent when the session
    /// belongs to no project, so an older summary still decodes.
    @Test func aSummaryNamesItsProjectOnlyWhenItHasOne() throws {
        var summary = SessionSummary(identifier: Self.identifier, folder: "work", command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 0))
        let plain = try JSONEncoder.messages.encode(summary)
        #expect(!String(decoding: plain, as: UTF8.self).contains("projectIdentifier"))
        summary.projectIdentifier = Self.identifier
        let text = String(decoding: try JSONEncoder.messages.encode(summary), as: UTF8.self)
        #expect(text.contains(#""projectIdentifier":"\#(Self.identifierText)""#))
        #expect(try JSONDecoder.messages.decode(SessionSummary.self, from: Data(text.utf8)) == summary)
    }

    @Test func theCapabilityIsOffWhenTheFieldIsMissing() throws {
        let older = Data(#"{"orderedResizeConfirmation":true,"sessionChanges":true}"#.utf8)
        #expect(try JSONDecoder.messages.decode(ServerCapabilities.self, from: older) == ServerCapabilities(orderedResizeConfirmation: true, sessionChanges: true))
        let offered = ServerCapabilities(orderedResizeConfirmation: true, sessionChanges: true, projectsAndSettings: true)
        #expect(try JSONDecoder.messages.decode(ServerCapabilities.self, from: JSONEncoder.messages.encode(offered)).projectsAndSettings)
    }

    /// An error names the message and never its fields, which hold a path.
    @Test func eachMessageHasAName() {
        #expect(ClientMessage.addProject(folder: "/secret", name: nil, currentFolder: nil).name == "addProject")
        #expect(ServerMessage.projectList([]).name == "projectList")
    }
}
