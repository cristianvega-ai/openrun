import Foundation

/// A session needs the user: its program asked for attention, or another
/// program named the session (decision of 2026-11-10). The alert stays
/// until the user types into the session or a client clears it.
public struct SessionAlert: Codable, Equatable, Sendable {
    /// What raised the alert.
    public enum Source: String, Codable, Sendable {
        /// The program rang the bell.
        case bell
        /// The program sent OSC 9, OSC 99 or OSC 777.
        case terminalNotification
        /// `openrun notify`, or another client, raised it.
        case notifyCommand
    }

    /// The text that the program or the client gave. It is empty for the
    /// bell. It holds no control character, no mark of text direction and no
    /// line separator, and at most `SessionSummary.textLimit` Unicode scalars.
    public var text: String
    public var raisedAt: Date
    public var source: Source

    public init(text: String, raisedAt: Date, source: Source) {
        self.text = SessionSummary.boundedText(text)
        self.raisedAt = raisedAt
        self.source = source
    }
}
