/// The filter of the second pane (proposal 11 of 2026-11-10). "Needs You"
/// is an entry of the first pane, so it is no filter here.
public enum SessionsFilter: String, CaseIterable, Sendable {
    case all
    case inProgress
    /// An agent that finished its turn and waits, or an idle terminal.
    case finished

    public var title: String {
        switch self {
        case .all: "All"
        case .inProgress: "In Progress"
        case .finished: "Finished"
        }
    }

    public func includes(_ row: SessionRowDisplay) -> Bool {
        switch self {
        case .all: true
        case .inProgress: row.isInProgress
        case .finished: !row.isInProgress
        }
    }
}
