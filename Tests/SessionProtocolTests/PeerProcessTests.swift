import Darwin
import Foundation
import Testing
@testable import SessionProtocol

@Suite struct PeerProcessTests {
    /// Both ends of a socket pair belong to this process, so the peer is
    /// this process in its own terminal session.
    @Test func thePeerOfASocketPairIsThisProcess() throws {
        let (first, second) = try MessageConnection.makePair()
        defer { first.shutdown(); second.shutdown() }
        let peer = try first.peerProcess()
        #expect(peer.processIdentifier == getpid())
        #expect(peer.terminalSessionIdentifier == getsid(0))
        #expect(peer.auditToken.count == MemoryLayout<audit_token_t>.size)
        #expect(try second.peerProcess() == peer)
    }

    /// The audit token names the process too. Its sixth value is the
    /// process identifier (`audit_token_to_pid`).
    @Test func theAuditTokenNamesTheSameProcess() throws {
        let (first, second) = try MessageConnection.makePair()
        defer { first.shutdown(); second.shutdown() }
        let peer = try first.peerProcess()
        let values = peer.auditToken.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        #expect(values.count == 8)
        #expect(pid_t(bitPattern: values[5]) == getpid())
    }
}
