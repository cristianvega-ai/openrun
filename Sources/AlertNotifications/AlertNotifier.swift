/// Shows notifications for sessions that need the user. The app uses the
/// notifications of macOS, and tests use a stand-in.
@MainActor
public protocol AlertNotifier: AnyObject {
    /// Shows a notification, in place of an older one for the same session.
    func post(_ notification: AlertNotification)
    /// Takes away the notification of a session whose alert ended.
    func remove(identifier: String)
    /// Runs with the identifier when the user opens a notification.
    var opened: ((String) -> Void)? { get set }
}
