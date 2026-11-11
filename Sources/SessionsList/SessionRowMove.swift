import Foundation

/// A drag of one row to another place in the user's own order. A filter
/// can hide rows, so the drop lands next to the visible row that it is
/// next to, and the hidden rows keep their places.
struct SessionRowMove: Equatable {
    var identifier: UUID
    /// The index of the row in the user's order after the move.
    var destination: Int

    /// - Parameters:
    ///   - order: Every row of the user's order.
    ///   - visible: The rows that the list shows, in the user's order.
    ///   - row: The index in `visible` of the dragged row.
    ///   - dropRow: The index in `visible` above which the user drops it.
    /// - Returns: `nil` when the move changes nothing.
    init?(order: [UUID], visible: [UUID], row: Int, dropRow: Int) {
        guard visible.indices.contains(row), let source = order.firstIndex(of: visible[row]) else { return nil }
        let identifier = visible[row]
        var others = visible
        others.remove(at: row)
        var remaining = order
        remaining.remove(at: source)
        let place = min(max(0, dropRow > row ? dropRow - 1 : dropRow), others.count)
        let destination: Int
        if place < others.count, let anchor = remaining.firstIndex(of: others[place]) {
            destination = anchor
        } else if let last = others.last, let anchor = remaining.firstIndex(of: last) {
            destination = anchor + 1
        } else {
            return nil
        }
        guard destination != source else { return nil }
        (self.identifier, self.destination) = (identifier, destination)
    }
}
