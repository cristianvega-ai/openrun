import Darwin
import Foundation

/// The program at the other end of a connected Unix socket.
///
/// The session process reads it once, when it accepts a connection and
/// before it reads a message. A program that has already ended by then has
/// no terminal session, so it cannot pass for a program outside every
/// session (see `specifications/ApprovalQuestion.tla`).
public struct PeerProcess: Equatable, Sendable {
    /// The process that connected, as the system recorded it at the connect.
    public let processIdentifier: pid_t
    /// The terminal session of that process at the moment of the reading,
    /// or nil when the process had ended.
    public let terminalSessionIdentifier: pid_t?
    /// The audit token of the process, for a check of its code signature.
    /// Unlike the process identifier, it can never name a later process.
    public let auditToken: Data

    public init(processIdentifier: pid_t, terminalSessionIdentifier: pid_t?, auditToken: Data) {
        self.processIdentifier = processIdentifier
        self.terminalSessionIdentifier = terminalSessionIdentifier
        self.auditToken = auditToken
    }

    public init(ofSocket descriptor: Int32) throws {
        var processIdentifier: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processIdentifier, &length) == 0 else {
            throw SessionProtocolError.failure(of: "getsockopt LOCAL_PEERPID")
        }
        var token = audit_token_t()
        length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else {
            throw SessionProtocolError.failure(of: "getsockopt LOCAL_PEERTOKEN")
        }
        let session = getsid(processIdentifier)
        self.processIdentifier = processIdentifier
        terminalSessionIdentifier = session > 0 ? session : nil
        auditToken = withUnsafeBytes(of: &token) { Data($0) }
    }
}
