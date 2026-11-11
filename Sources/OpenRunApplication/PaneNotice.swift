/// What the third pane says in place of a session that it cannot show.
struct PaneNotice: Equatable {
    var title: String
    /// The reason, as the session process or the system gave it.
    var message: String
    /// The title of a button that tries again, or `nil` when the app
    /// tries again by itself.
    var buttonTitle: String?

    /// The app does not hear the session process. The connection comes
    /// back by itself, so the notice has no button.
    static func noSessionProcess(reason: String) -> PaneNotice {
        PaneNotice(title: "No Connection to the Session Process", message: reason + "\nOpenRun tries again by itself.", buttonTitle: nil)
    }

    /// The pane of a session that still runs lost its connection, and the
    /// user saw why. A new try is the choice of the user, so a failure
    /// that stays does not show again and again.
    static let lostSession = PaneNotice(
        title: "The Connection to This Session Ended", message: "The session still runs in the session process.", buttonTitle: "Connect Again")
}
