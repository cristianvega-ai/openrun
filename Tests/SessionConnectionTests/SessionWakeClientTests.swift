import Darwin
import Foundation
import SessionLaunch
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

/// A test cannot use the default socket or register a launch agent. So
/// these tests pass their own wake, on a socket of the test.
@Suite struct SessionWakeClientTests {
    /// A socket path holds at most 103 bytes, and `TMPDIR` can be longer.
    private static func socketLocation(named name: String) throws -> SocketLocation {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let folder = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return try SocketLocation(path: (folder as NSString).appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).socket"))
    }

    @Test func aClientSendsOnlyOneWake() throws {
        let location = try Self.socketLocation(named: "silent")
        let wakes = Mutex(0)
        #expect(throws: SessionConnectionError.noSessionProcess(socketPath: location.path)) {
            try SessionClient(location: location) { () throws(SessionWakeFailure) in wakes.withLock { $0 += 1 } }
        }
        #expect(wakes.withLock { $0 } == 1)
    }

    @Test func aWakeThatFailsIsTheErrorOfTheClient() throws {
        let location = try Self.socketLocation(named: "unstarted")
        let error = #expect(throws: SessionConnectionError.self) {
            try SessionClient(location: location) { () throws(SessionWakeFailure) in throw .timedOut(limit: .seconds(15)) }
        }
        #expect(error == .wakeFailed(.timedOut(limit: .seconds(15))))
        #expect(error?.description.contains("Open OpenRun to register it again.") == true)
    }

    /// Only the path is compared. Nothing connects to the default socket.
    @Test func onlyTheDefaultSocketHasTheWakeOfTheLaunchAgent() throws {
        #expect(SessionClient.launchAgentWake(for: try SocketLocation(path: SocketLocation.defaultPath)) != nil)
        #expect(SessionClient.launchAgentWake(for: try Self.socketLocation(named: "other")) == nil)
    }
}
