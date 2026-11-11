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

    /// An error names the message and never its fields, which hold a path.
    @Test func eachMessageHasAName() {
        #expect(ClientMessage.addProject(folder: "/secret", name: nil, currentFolder: nil).name == "addProject")
        #expect(ServerMessage.projectList([]).name == "projectList")
    }
}
