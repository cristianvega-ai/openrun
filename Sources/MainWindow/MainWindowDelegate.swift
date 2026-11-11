/// What the main window tells its host.
@MainActor
public protocol MainWindowDelegate: AnyObject {
    /// The content of the third pane became active: the window is key and
    /// the keyboard focus is in the content. A session pane then takes its
    /// grid size back (decision of 2026-10-27).
    func mainWindowContentDidBecomeActive(_ window: MainWindowController)
    func mainWindowContentDidResignActive(_ window: MainWindowController)
    /// The user closed the window. The sessions keep running.
    func mainWindowWillClose(_ window: MainWindowController)
}
