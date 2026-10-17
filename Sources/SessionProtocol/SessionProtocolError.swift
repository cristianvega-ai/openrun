import Darwin

/// A session socket could not be used, or the other side broke the protocol.
public enum SessionProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A Unix socket address holds only a short path.
    case socketPathTooLong(path: String, limit: Int)
    /// A frame announced more bytes than the protocol allows.
    case frameTooLarge(length: Int, limit: Int)
    /// A frame did not follow the format.
    case malformedFrame(reason: String)
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)
    /// A message arrived that does not fit this point of the conversation.
    case unexpectedMessage(description: String)
    /// The folder of the socket belongs to another user, who could put a
    /// socket of their own at the path.
    case socketFolderOfAnotherUser(folder: String, owner: uid_t)
    /// Users other than the owner may write to the folder of the socket, so
    /// they could put a socket of their own at the path.
    case socketFolderWritableByOthers(folder: String, mode: mode_t)
    /// An entry of the access control list of the socket's folder lets
    /// another user or a group add or remove files in it, whatever the mode
    /// says.
    case socketFolderWritableThroughAccessControlList(folder: String)
    /// What should be the folder of the socket is a file of another kind.
    case socketFolderIsNotADirectory(folder: String)

    public var description: String {
        switch self {
        case .socketPathTooLong(let path, let limit):
            "The socket path is too long: a Unix socket path holds at most \(limit) bytes, and \(path) has \(path.utf8.count). Choose a shorter path with --socket."
        case .frameTooLarge(let length, let limit):
            "A frame of \(length) bytes is larger than the limit of \(limit) bytes."
        case .malformedFrame(let reason):
            "A frame is malformed: \(reason)."
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        case .unexpectedMessage(let description):
            "An unexpected message arrived: \(description)."
        case .socketFolderOfAnotherUser(let folder, let owner):
            "The socket folder \(folder) belongs to another user (user \(owner)), who could put a socket of their own there. Choose a socket in a folder of your own with --socket."
        case .socketFolderWritableByOthers(let folder, let mode):
            "Other users can write to the socket folder \(folder) (mode \(String(mode, radix: 8))), so one of them could put a socket of their own there. Choose a socket in a folder that only you can write to with --socket, or run chmod go-w on the folder."
        case .socketFolderWritableThroughAccessControlList(let folder):
            "The access control list of the socket folder \(folder) lets other users add or remove files in it, so one of them could put a socket of their own there. Choose a socket in a folder that only you can write to with --socket, or remove the entry (ls -led shows the list, and chmod -a removes an entry)."
        case .socketFolderIsNotADirectory(let folder):
            "The socket folder \(folder) is not a folder. Choose a socket in a folder of your own with --socket."
        }
    }

    /// Captures `errno` right after a failed call.
    static func failure(of function: String) -> SessionProtocolError {
        .systemCallFailed(function: function, code: errno)
    }
}
