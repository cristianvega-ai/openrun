import Foundation

/// The order of the second pane. The newest comes first in the orders by
/// time, because the user looks for recent work.
public enum SessionsOrder: String, CaseIterable, Sendable {
    /// The user's own order, which a drag changes.
    case manual
    case lastActivity
    case name
    case startTime

    public var title: String {
        switch self {
        case .manual: "Manual"
        case .lastActivity: "Last Activity"
        case .name: "Name"
        case .startTime: "Start Time"
        }
    }

    /// The rows in this order. Rows that are equal keep the user's order,
    /// so the list does not jump between two updates.
    public func arranged(_ rows: [SessionRowDisplay]) -> [SessionRowDisplay] {
        let indexed = Array(rows.enumerated())
        return indexed.sorted { left, right in
            let (first, second) = (left.element, right.element)
            switch self {
            case .manual: break
            case .lastActivity where first.lastActivity != second.lastActivity: return first.lastActivity > second.lastActivity
            case .startTime where first.startTime != second.startTime: return first.startTime > second.startTime
            case .name:
                let comparison = first.title.localizedStandardCompare(second.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            default: break
            }
            return left.offset < right.offset
        }.map(\.element)
    }
}
