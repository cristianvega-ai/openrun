import Darwin
import Foundation
import Testing
@testable import SessionProtocol

@Suite struct SocketLocationTests {
    /// The absolute path that `resolve` makes. A folder with a long path pushes
    /// the result over the byte limit, and the error then carries that same
    /// path, so these tests give the same answer from any folder.
    private func absolutePath(flag: String?, environment: [String: String]) throws -> String {
        do {
            return try SocketLocation.resolve(flag: flag, environment: environment).path
        } catch SessionProtocolError.socketPathTooLong(let path, _) {
            return path
        }
    }

    @Test func theDefaultLivesInApplicationSupport() {
        #expect(SocketLocation.defaultPath.hasSuffix("/Library/Application Support/OpenRun/session.socket"))
    }

    @Test func theFlagBeatsTheEnvironmentBeatsTheDefault() throws {
        let environment = ["OPENRUN_SOCKET": "/run/from-environment"]
        #expect(try SocketLocation.resolve(flag: "/run/from-flag", environment: environment).path == "/run/from-flag")
        #expect(try SocketLocation.resolve(flag: nil, environment: environment).path == "/run/from-environment")
        #expect(try SocketLocation.resolve(flag: nil, environment: [:]).path == SocketLocation.defaultPath)
        #expect(try SocketLocation.resolve(flag: "", environment: [:]).isDefault)
    }

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

    @Test func aRelativePathIsMadeAbsoluteAgainstTheCurrentFolder() throws {
        let current = FileManager.default.currentDirectoryPath as NSString
        #expect(try absolutePath(flag: "session.socket", environment: [:]) == current.appendingPathComponent("session.socket"))
        #expect(try absolutePath(flag: nil, environment: ["OPENRUN_SOCKET": "sub/session.socket"]) == current.appendingPathComponent("sub/session.socket"))
        #expect(try absolutePath(flag: "/run/session.socket", environment: [:]) == "/run/session.socket")
    }

    @Test func aRelativePathWithParentFoldersStaysShort() throws {
        let current = FileManager.default.currentDirectoryPath as NSString
        let parent = current.deletingLastPathComponent as NSString
        let name = current.lastPathComponent
        #expect(try absolutePath(flag: "../\(name)/./session.socket", environment: [:]) == current.appendingPathComponent("session.socket"))
        #expect(try absolutePath(flag: "../other/session.socket", environment: [:]) == parent.appendingPathComponent("other/session.socket"))
    }

    @Test func aBareFileNameLivesInTheCurrentFolder() throws {
        let path = try absolutePath(flag: "session.socket", environment: [:])
        #expect((path as NSString).deletingLastPathComponent == FileManager.default.currentDirectoryPath)
    }

}
