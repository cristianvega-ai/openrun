import AlertNotifications
import AppKit
import ListContent
import SessionOverview
import SessionProtocol

/// The alerts of the sessions: their end when the user comes to the
/// session, the notifications of macOS, and the count on the Dock icon
/// (decision of 2026-11-10).
extension Workspace {
    /// A batch of changes came. A new alert of a session that the user
    /// does not look at gives a notification, and an alert that ended
    /// takes its notification away.
    func alertsChanged(from previous: SessionOverview) {
        let overview = connection.overview
        for session in overview.sessions where session.alert != previous.session(session.identifier)?.alert {
            let identifier = SessionSummary.text(for: session.identifier)
            guard let alert = session.alert else {
                notifier.remove(identifier: identifier)
                continue
            }
            guard session.identifier != sessionInView, settings.showsNotifications else { continue }
            let body = alert.text.isEmpty ? SessionRowFacts.alertWithoutText : alert.text
            notifier.post(AlertNotification(identifier: identifier, title: SessionRowFacts.title(of: session, home: home), body: body))
        }
        for session in previous.sessions where session.alert != nil && overview.session(session.identifier) == nil {
            notifier.remove(identifier: SessionSummary.text(for: session.identifier))
        }
        if let session = sessionInView { clearAlert(of: session) }
    }

    /// Ends the alert of a session, because the user came to it. One
    /// request goes out for each alert, also when the feed is slow.
    func clearAlert(of session: UUID) {
        guard let alert = connection.overview.session(session)?.alert, clearedAlerts[session] != alert.raisedAt else { return }
        clearedAlerts[session] = alert.raisedAt
        requests.perform({ try $0.clearAlert(session: session) }, then: { _ in })
    }

    /// The user opened a notification. The window comes to the front, and
    /// the row of the session takes the selection and the keyboard focus.
    func openNotification(_ identifier: String) {
        guard let session = UUID(uuidString: identifier), let row = layout.row(showing: session) else { return }
        activateApplication()
        window.showWindow()
        sessionToSelect = session
        select(row: row.identifier)
    }

    /// Shows the number of rows that need the user on the Dock icon.
    func updateBadge(_ count: Int) {
        guard count != badgeCount else { return }
        badgeCount = count
        setBadge(count)
    }
}
