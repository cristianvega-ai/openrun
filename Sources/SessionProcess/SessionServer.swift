import Foundation
import SessionProtocol
import TerminalEmulation

actor SessionServer {

    /// The session process runs in the foreground and logs to standard error.
    /// A message can include text that a client chose, such as a folder, a
    /// command or an error message, and a terminal that shows the log must not
    /// obey it. Every log line passes here, so one escape covers them all, and
    /// a value with a line break cannot forge a second line.
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("openrun-session: \(PrintableText.escaping(message))\n".utf8))
    }
}
