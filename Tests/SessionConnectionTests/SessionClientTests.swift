import Darwin
import Foundation
import SessionProtocol
import Testing
@testable import SessionConnection

@Suite struct SessionClientTests {
    /// A socket path holds at most 103 bytes, and `TMPDIR` can be longer.
    private static func socketLocation(named name: String) throws -> SocketLocation {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let folder = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return try SocketLocation(path: (folder as NSString).appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).socket"))
    }

    @Test func aSocketThatDoesNotExistMeansNoSessionProcess() throws {
        let location = try Self.socketLocation(named: "absent")
        #expect(throws: SessionConnectionError.noSessionProcess(socketPath: location.path)) {
            try SessionClient(location: location)
        }
    }

    /// A session process that crashed leaves its socket file, and nothing
    /// accepts connections on it.
    @Test func aSocketThatNobodyListensOnMeansNoSessionProcess() throws {
        let location = try Self.socketLocation(named: "stale")
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { unlink(location.path) }
        try #require(location.withAddress { bind(descriptor, $0, $1) } == 0)
        close(descriptor)
        let error = #expect(throws: SessionConnectionError.self) { try SessionClient(location: location) }
        #expect(error == .noSessionProcess(socketPath: location.path))
        #expect(error?.description == "No session process answers on \(location.path).")
    }

    @Test func aSessionProcessOfAnotherVersionIsAProtocolFailure() throws {
        let (clientSide, sessionSide) = try MessageConnection.makePair()
        let theirs = MessageFrame.protocolVersion + 1
        try sessionSide.send(ServerMessage.hello(protocolVersion: theirs))
        let error = #expect(throws: SessionConnectionError.self) { try SessionClient(greeting: clientSide) }
        let protocolError = SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: theirs)
        #expect(error == .protocolFailure(protocolError))
        #expect(error?.description == protocolError.description)
    }
}
