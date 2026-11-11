import AppKit

/// The width of a list is the user's choice, made by a drag of its edge. A
/// narrow window or a show can squeeze a list down to its minimum, but the
/// chosen width stays, and only chosen widths are saved.
extension MainWindowController {
    func dragStarted() {
        widthsAtDragStart = (projectsList.view.frame.width, sessionsList.view.frame.width)
        contentPane.beginPaneResize()
    }

    /// Only a list whose edge moved has a new choice. A list that a squeeze
    /// keeps narrow keeps its choice.
    func dragEnded() {
        let (projects, sessions) = (projectsList.view.frame.width, sessionsList.view.frame.width)
        if !layout.projectsHidden, projects != widthsAtDragStart.projects { layout.projectsWidth = projects }
        if !layout.sessionsHidden, sessions != widthsAtDragStart.sessions { layout.sessionsWidth = sessions }
        paneResizeEnded()
    }
}
