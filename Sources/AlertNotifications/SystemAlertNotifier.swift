import Foundation
import UserNotifications

/// The notifications of macOS. It asks for the permission at the first
/// alert, not at the start of the app. When the user refuses, nothing
/// shows, and the app stays quiet.
@MainActor
public final class SystemAlertNotifier: NSObject, AlertNotifier, UNUserNotificationCenterDelegate {
    public var opened: ((String) -> Void)?
    /// The center exists only for a program in an app bundle. A program
    /// of `swift build` has none, and a call for it would stop the program.
    private let center: UNUserNotificationCenter?

    public override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
    }

    public func post(_ notification: AlertNotification) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        (content.title, content.body) = (notification.title, notification.body)
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        // The first call shows the question of macOS. Later calls answer at once.
        center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    public func remove(identifier: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// The app is in front, and the alert is for a session that the user
    /// does not look at, so the notification shows.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        DispatchQueue.main.async { MainActor.assumeIsolated { self.opened?(identifier) } }
        completionHandler()
    }
}
