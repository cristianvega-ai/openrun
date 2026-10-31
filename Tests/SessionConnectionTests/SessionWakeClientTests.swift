import Darwin
import Foundation
import SessionLaunch
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

/// A test cannot use the default socket or register a launch agent. So
/// these tests pass their own wake, on a socket of the test, and the wake
/// starts a stand-in session process.
@Suite struct SessionWakeClientTests {
    /// A socket path holds at most 103 bytes, and `TMPDIR` can be longer.
    private static func socketLocation(named name: String) throws -> SocketLocation {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let folder = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return try SocketLocation(path: (folder as NSString).appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).socket"))
    }

    /// Listens on the socket and takes one connection. It greets the
    /// client, or closes the connection before hello, as a launch agent
    /// does that ends because it is idle.
    private static func standIn(on location: SocketLocation, greets: Bool) throws {
        unlink(location.path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(location.withAddress { bind(listener, $0, $1) } == 0 && listen(listener, 1) == 0)
        Thread {
            let accepted = accept(listener, nil, nil)
            close(listener)
            let connection = MessageConnection(descriptor: accepted)
            if greets { try? connection.greetClient() }
            connection.shutdown()
        }.start()
    }

    @Test(arguments: [false, true])
    func aClientSendsOneWakeWhenNothingListens(leavesAStaleSocketFile: Bool) throws {
        let location = try Self.socketLocation(named: leavesAStaleSocketFile ? "stale" : "absent")
        defer { unlink(location.path) }
        if leavesAStaleSocketFile {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            try #require(location.withAddress { bind(descriptor, $0, $1) } == 0)
            close(descriptor)
        }
        let wakes = Mutex(0)
        _ = try SessionClient(location: location) { () throws(SessionWakeFailure) in
            wakes.withLock { $0 += 1 }
            try? Self.standIn(on: location, greets: true)
        }
        #expect(wakes.withLock { $0 } == 1)
    }

    @Test func aConnectionThatClosesBeforeHelloLeadsToOneWake() throws {
        let location = try Self.socketLocation(named: "closing")
        defer { unlink(location.path) }
        try Self.standIn(on: location, greets: false)
        let wakes = Mutex(0)
        _ = try SessionClient(location: location) { () throws(SessionWakeFailure) in
            wakes.withLock { $0 += 1 }
            try? Self.standIn(on: location, greets: true)
        }
        #expect(wakes.withLock { $0 } == 1)
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
        #expect(error?.description == "The session process did not answer the request to start within 15 seconds. If the agent does not start after a rebuild, open OpenRun and choose File > Register Session Process Again.")
    }

    /// Only the path is compared. Nothing connects to the default socket.
    @Test func onlyTheDefaultSocketHasTheWakeOfTheLaunchAgent() throws {
        #expect(SessionClient.launchAgentWake(for: try SocketLocation(path: SocketLocation.defaultPath)) != nil)
        #expect(SessionClient.launchAgentWake(for: try Self.socketLocation(named: "other")) == nil)
    }
}
