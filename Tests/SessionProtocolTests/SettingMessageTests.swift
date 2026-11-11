import Foundation
import Testing
@testable import SessionProtocol

@Suite struct SettingMessageTests {
    @Test func eachMessageHasTheTextOfTheDocument() throws {
        let expected: [(any FramedMessage, String)] = [
            (ClientMessage.listSettings, #"{"listSettings":{}}"#),
            (ClientMessage.changeSetting(name: "font-size", text: "14"), #"{"changeSetting":{"name":"font-size","text":"14"}}"#),
            (
                ServerMessage.settingList([SettingSummary(name: "session-limit", text: "100", isProtected: true)]),
                #"{"settingList":{"_0":[{"isProtected":true,"name":"session-limit","text":"100"}]}}"#
            ),
        ]
        for (message, text) in expected {
            #expect(String(decoding: try message.frame().payload, as: UTF8.self) == text)
            if let client = message as? ClientMessage { #expect(try ClientMessage(frame: client.frame()) == client) }
            if let server = message as? ServerMessage { #expect(try ServerMessage(frame: server.frame()) == server) }
        }
        #expect(ClientMessage.changeSetting(name: "theme", text: "secret").name == "changeSetting")
    }
}
