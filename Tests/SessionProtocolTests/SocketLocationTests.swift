import Darwin
import Foundation
import Testing
@testable import SessionProtocol

@Suite struct SocketLocationTests {

    @Test func aPathAtTheLimitWorksAndOneByteMoreFails() throws {
        let limit = SocketLocation.pathByteLimit
        let fits = "/" + String(repeating: "a", count: limit - 1)
        #expect(try SocketLocation(path: fits).path == fits)
        #expect(throws: SessionProtocolError.socketPathTooLong(path: fits + "a", limit: limit)) {
            try SocketLocation(path: fits + "a")
        }
    }

    @Test func theErrorMessageNamesThePathAndTheFix() {
        let error = SessionProtocolError.socketPathTooLong(path: "/very/long", limit: 103)
        #expect(error.description.contains("/very/long"))
        #expect(error.description.contains("--socket"))
    }

    @Test func theFolderIsTheParentOfTheSocketFile() throws {
        #expect(try SocketLocation(path: "/run/openrun/session.socket").folder == "/run/openrun")
    }
}
