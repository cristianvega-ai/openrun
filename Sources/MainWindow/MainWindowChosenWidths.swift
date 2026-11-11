import AppKit

/// The width of a list is the user's choice, made by a drag of its edge. A
/// narrow window or a show can squeeze a list down to its minimum, but the
/// chosen width stays. When room comes back, each list grows back to it
/// before the content takes the spare room.
extension MainWindowController {
    /// Above the hold of every pane, so a list takes room back from the
    /// content. Below the minimums and the size of the window, so a squeeze
    /// wins over it.
    static let chosenWidthPriority = NSLayoutConstraint.Priority(280)

    func makeChosenWidthConstraints() {
        for (view, width) in [(projectsList.view, layout.projectsWidth), (sessionsList.view, layout.sessionsWidth)] {
            let constraint = view.widthAnchor.constraint(equalToConstant: width)
            constraint.priority = Self.chosenWidthPriority
            chosenWidths.append(constraint)
        }
        updateChosenWidths()
    }

    /// A hidden list asks for no width, so the constraint of its choice is off.
    func updateChosenWidths() {
        chosenWidths[0].constant = layout.projectsWidth
        chosenWidths[1].constant = layout.sessionsWidth
        chosenWidths[0].isActive = !layout.projectsHidden
        chosenWidths[1].isActive = !layout.sessionsHidden
    }

    /// The edge follows the pointer, so the old choice does not pull at it.
    func dragStarted() {
        widthsAtDragStart = (projectsList.view.frame.width, sessionsList.view.frame.width)
        chosenWidths.forEach { $0.isActive = false }
        contentPane.beginPaneResize()
    }

    /// Only a list whose edge moved has a new choice. A list that a squeeze
    /// keeps narrow keeps its choice.
    func dragEnded() {
        let (projects, sessions) = (projectsList.view.frame.width, sessionsList.view.frame.width)
        if !layout.projectsHidden, projects != widthsAtDragStart.projects { layout.projectsWidth = projects }
        if !layout.sessionsHidden, sessions != widthsAtDragStart.sessions { layout.sessionsWidth = sessions }
        updateChosenWidths()
        paneResizeEnded()
    }
}
