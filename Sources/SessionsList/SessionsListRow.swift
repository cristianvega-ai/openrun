import Foundation

/// One row of the second pane as the table shows it.
struct SessionsListRow: Equatable {
    /// The mark at the end of the title line. Only the mark of a row that
    /// needs the user has a strong color (decision of 2026-10-26).
    enum Mark: Equatable {
        case attention
        case progress
        /// The quiet age of the last activity of a finished row.
        case age(String)
    }

    var identifier: UUID
    var title: String
    /// The whole second line: the alert, or the place of the work.
    var secondLine: String
    /// The parts of the place. The cell shortens the folder from its start
    /// when the line does not fit, so the model and the branch stay.
    var model: String?
    var folder: String
    var branch: String?
    var symbol: String
    var mark: Mark
    var accessibilityLabel: String

    /// A row that needs the user shows the alert in place of the second
    /// line, because the alert is what the user must read first.
    init(_ display: SessionRowDisplay, now: Date) {
        (identifier, title) = (display.identifier, display.title)
        (folder, branch) = (display.folder, display.branch)
        // A thread shows only the short name of its model, so the line keeps
        // room for the folder (the owner's decision of 2026-11-10).
        if case .agentThread(_, let model, _) = display.kind { self.model = model }
        let details = [model, folder, branch].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        symbol = display.kind == .terminal ? "terminal" : "bubble.left"
        let state: String
        if let alert = display.alert {
            (mark, secondLine, state) = (.attention, alert, "needs you")
        } else if display.isInProgress {
            (mark, secondLine, state) = (.progress, details, "in progress")
        } else {
            (mark, secondLine, state) = (.age(Self.age(of: display.lastActivity, now: now)), details, "finished")
        }
        let kind = display.kind == .terminal ? "terminal" : ""
        accessibilityLabel = [title, kind, secondLine, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The place of the work in one line that fits. Only the folder gets
    /// shorter, from its start, so the model and the branch stay whole.
    static func place(model: String?, folder: String, branch: String?, fits: (String) -> Bool) -> String {
        func line(_ shownFolder: String) -> String {
            [model, shownFolder, branch].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        guard !fits(line(folder)), !folder.isEmpty else { return line(folder) }
        var (shortest, longest) = (0, folder.count - 1)
        while shortest < longest {
            let middle = (shortest + longest + 1) / 2
            if fits(line("…" + folder.suffix(middle))) { shortest = middle } else { longest = middle - 1 }
        }
        return line("…" + folder.suffix(shortest))
    }

    /// A short age, such as "now", "5m", "3h", "2d" or "6w".
    static func age(of date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        switch minutes {
        case ..<1: return "now"
        case ..<60: return "\(minutes)m"
        case ..<(24 * 60): return "\(minutes / 60)h"
        case ..<(7 * 24 * 60): return "\(minutes / (24 * 60))d"
        default: return "\(minutes / (7 * 24 * 60))w"
        }
    }
}
