import Foundation
import os
import TerminalEmulation

/// The log of the session process.
///
/// launchd sends the standard error of the launch agent to /dev/null, so
/// each line also goes to the unified log. Other programs of the user can
/// read that log, and it stays after the process ends. So the parts that
/// hold a path, a command line or an error text are private there.
enum SessionLog {
    static let subsystem = "ai.cristianvega.openrun"
    private static let logger = Logger(subsystem: subsystem, category: "session-process")

    /// Writes one line to standard error and to the unified log.
    ///
    /// A line can hold text that a client chose, and a terminal that shows
    /// the log must not obey it. So every line is escaped, and a value with
    /// a line break cannot forge a second line.
    ///
    /// - Parameters:
    ///   - text: Words of OpenRun with counts and identifiers only. They are
    ///     public in the unified log.
    ///   - detail: A path, a command line or an error text after the text.
    ///     It is private in the unified log.
    static func write(_ text: String, detail: String = "") {
        let shownText = PrintableText.escaping(text)
        let shownDetail = PrintableText.escaping(detail)
        if shownDetail.isEmpty {
            logger.log("\(shownText, privacy: .public)")
        } else {
            logger.log("\(shownText, privacy: .public)\(shownDetail, privacy: .private)")
        }
        FileHandle.standardError.write(Data("openrun-session: \(shownText)\(shownDetail)\n".utf8))
    }
}
