/// A notification of macOS for a session that needs the user (decision of
/// 2026-11-10). A program chose the texts. The session process bounded and
/// cleaned them, and the system shows them as plain text.
public struct AlertNotification: Equatable, Sendable {
    /// Names the session. A newer notification with the same identifier
    /// takes the place of the older one.
    public var identifier: String
    /// The title of the row of the session.
    public var title: String
    /// The text of the alert.
    public var body: String

    public init(identifier: String, title: String, body: String) {
        (self.identifier, self.title, self.body) = (identifier, title, body)
    }
}
