import AppKit
import Foundation
@testable import TerminalView
@testable import SessionPane

/// Lets the main thread work until `condition` is true or `seconds` have passed.
/// The pane gets the events of its session through the main queue, which
/// runs only while the test waits.
@MainActor
func waitOnMainThread(seconds: Double = 5, until condition: () -> Bool) async {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end {
        runLoopTurn()
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// One short turn of the main run loop. Swift does not let an async function run it.
@MainActor
private func runLoopTurn() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
}

/// Plays the host of a pane and keeps what the pane reports.
@MainActor
final class RecordingHost: SessionPaneDelegate {
    var titles: [String] = []
    var minimumSizeReports = 0
    var ends = 0

    func sessionPane(_ pane: SessionPaneController, didChangeTitle title: String) { titles.append(title) }
    func sessionPaneDidChangeMinimumSize(_ pane: SessionPaneController) { minimumSizeReports += 1 }
    func sessionPaneDidEnd(_ pane: SessionPaneController) { ends += 1 }
}

extension TerminalView {
    /// The text on the screen of the view.
    var screenText: String { String(decoding: (try? terminal.formatted(.plainText)) ?? [], as: UTF8.self) }
}

