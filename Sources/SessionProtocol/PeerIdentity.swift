import Darwin

/// The user that a program runs as, on one end of a Unix socket.
///
/// Both sides of the socket talk only to the same user. The modes of the
/// socket and its folder keep other users out already. The check of the peer
/// also holds when a folder or a file mode is wrong.
public struct PeerIdentity: Equatable, Sendable {
    public let userIdentifier: uid_t

    public init(userIdentifier: uid_t) {
        self.userIdentifier = userIdentifier
    }

    /// The user that this process runs as.
    public static var currentUser: PeerIdentity {
        PeerIdentity(userIdentifier: geteuid())
    }

    /// The user of the program at the other end of a connected Unix socket,
    /// as the system recorded it when the connection was made.
    public init(ofSocket descriptor: Int32) throws {
        var user: uid_t = 0
        var group: gid_t = 0
        guard getpeereid(descriptor, &user, &group) == 0 else {
            throw SessionProtocolError.failure(of: "getpeereid")
        }
        userIdentifier = user
    }
}
