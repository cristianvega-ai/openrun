import Darwin
import Foundation
import Synchronization

public enum SocketSecurityHarness {

    /// The mode bits of a file or folder, or nil when it does not exist.
    public static func mode(of path: String) -> mode_t? {
        var status = stat()
        guard stat(path, &status) == 0 else { return nil }
        return status.st_mode & 0o7777
    }

    /// The lock file that a session process holds next to its socket.
    public static func lockPath(forSocket socketPath: String) -> String {
        socketPath + ".lock"
    }
}
