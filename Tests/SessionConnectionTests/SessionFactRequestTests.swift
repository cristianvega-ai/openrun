import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

@Suite struct SessionFactRequestTests {
    @Test func eachRequestSendsItsMessageAndTakesTheAcknowledgement() throws {
        let identifier = UUID()
        let received = Mutex<[ClientMessage]>([])
        let client = try SessionClient.standIn { sessionSide in
            while let message = try sessionSide.receive(ClientMessage.self) {
                received.withLock { $0.append(message) }
                try sessionSide.send(ServerMessage.acknowledged)
            }
        }
        try client.rename(session: identifier, to: "Release")
        try client.rename(session: identifier, to: nil)
        try client.raiseAlert(session: identifier, text: "Done")
        try client.clearAlert(session: identifier)
        #expect(received.withLock { $0 } == [
            .renameSession(identifier: identifier, name: "Release"), .renameSession(identifier: identifier, name: nil),
            .raiseSessionAlert(identifier: identifier, text: "Done"), .clearSessionAlert(identifier: identifier),
        ])
    }

    @Test func aRefusalBecomesAnError() throws {
        let failure = SessionFailure(reason: .invalidRequest, message: "Only a program outside every session may rename it.")
        let client = try SessionClient.standIn { sessionSide in
            _ = try sessionSide.receive(ClientMessage.self)
            try sessionSide.send(ServerMessage.failure(failure))
        }
        #expect(throws: SessionConnectionError.requestFailed(failure)) { try client.rename(session: UUID(), to: "x") }
    }

    @Test func theProjectAndSettingRequestsSendTheirMessages() throws {
        let identifier = UUID()
        let project = ProjectSummary(identifier: identifier, name: nil, folder: "/work/app")
        let setting = SettingSummary(name: "font-size", text: "13", isProtected: false)
        let received = Mutex<[ClientMessage]>([])
        let client = try SessionClient.standIn { sessionSide in
            while let message = try sessionSide.receive(ClientMessage.self) {
                received.withLock { $0.append(message) }
                switch message {
                case .listProjects: try sessionSide.send(ServerMessage.projectList([project]))
                case .addProject: try sessionSide.send(ServerMessage.projectAdded(project))
                case .listSettings: try sessionSide.send(ServerMessage.settingList([setting]))
                default: try sessionSide.send(ServerMessage.acknowledged)
                }
            }
        }
        #expect(try client.projects() == [project])
        #expect(try client.addProject(folder: "app", name: nil, currentFolder: "/work") == project)
        try client.removeProject(identifier)
        try client.renameProject(identifier, to: "App")
        try client.moveProject(identifier, to: 2)
        #expect(try client.settings() == [setting])
        try client.changeSetting(named: "font-size", to: "14")
        #expect(received.withLock { $0 } == [
            .listProjects, .addProject(folder: "app", name: nil, currentFolder: "/work"), .removeProject(identifier: identifier),
            .renameProject(identifier: identifier, name: "App"), .moveProject(identifier: identifier, place: 2),
            .listSettings, .changeSetting(name: "font-size", text: "14"),
        ])
    }

    @Test func aProjectListAnswerToAnAddIsUnexpected() throws {
        let client = try SessionClient.standIn { sessionSide in
            _ = try sessionSide.receive(ClientMessage.self)
            try sessionSide.send(ServerMessage.projectList([]))
        }
        #expect(throws: SessionConnectionError.unexpectedAnswer(request: "project add")) {
            try client.addProject(folder: "/work", name: nil, currentFolder: nil)
        }
    }
}
