import Testing
@testable import AlertNotifications

@MainActor @Suite struct SystemAlertNotifierTests {
    /// The test program has no app bundle, as a program of `swift build`
    /// has none. The notifier must then do nothing, and must not stop.
    @Test func aProgramOutsideAnAppBundleStaysQuiet() {
        let notifier = SystemAlertNotifier()
        var openedIdentifiers: [String] = []
        notifier.opened = { openedIdentifiers.append($0) }
        notifier.post(AlertNotification(identifier: "a", title: "zsh", body: "Done"))
        notifier.remove(identifier: "a")
        #expect(openedIdentifiers.isEmpty)
    }

    @Test func aNotificationHoldsTheTextsOfItsSession() {
        let notification = AlertNotification(identifier: "a", title: "Build", body: "Allow the edit?")
        #expect(notification == AlertNotification(identifier: "a", title: "Build", body: "Allow the edit?"))
        #expect(notification != AlertNotification(identifier: "b", title: "Build", body: "Allow the edit?"))
    }
}
