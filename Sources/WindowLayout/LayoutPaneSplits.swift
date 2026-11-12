import Foundation

/// The changes of a pane that a split of the third pane needs (decision
/// of 2026-11-10 on the rows).
extension LayoutPane {
    /// The sessions and the threads of the pane in reading order: the
    /// first half of each split before the second.
    public var leaves: [UUID] {
        switch self {
        case .session(let identifier), .thread(let identifier): [identifier]
        case .split(let split): split.first.leaves + split.second.leaves
        }
    }

    /// The pane with `new` beside the session or the thread `leaf`. The
    /// leaf becomes the first half of a split, and `new` the second.
    /// Unchanged when the pane does not hold the leaf.
    public func splitting(_ leaf: UUID, with new: LayoutPane, direction: LayoutSplit.Direction) -> LayoutPane {
        switch self {
        case .session(let identifier), .thread(let identifier):
            return identifier == leaf ? .split(LayoutSplit(direction: direction, first: self, second: new)) : self
        case .split(var split):
            split.first = split.first.splitting(leaf, with: new, direction: direction)
            split.second = split.second.splitting(leaf, with: new, direction: direction)
            return .split(split)
        }
    }

    /// The pane with a new share for the first half of one split: the
    /// split whose second half starts with `leaf`. A leaf starts the
    /// second half of at most one split, so it names the split.
    public func settingFraction(_ fraction: Double, ofSplitBefore leaf: UUID) -> LayoutPane {
        guard case .split(var split) = self else { return self }
        if split.second.leaves.first == leaf {
            split = LayoutSplit(direction: split.direction, fraction: fraction, first: split.first, second: split.second)
        } else {
            split.first = split.first.settingFraction(fraction, ofSplitBefore: leaf)
            split.second = split.second.settingFraction(fraction, ofSplitBefore: leaf)
        }
        return .split(split)
    }
}

extension WindowLayout {
    /// Puts a new session beside a session or a thread, in the row that
    /// shows it. A row of its own that the new session got goes away.
    ///
    /// - Returns: False when no row shows `leaf`. Nothing changes then.
    @discardableResult
    public mutating func split(_ leaf: UUID, with session: UUID, direction: LayoutSplit.Direction) -> Bool {
        guard let index = rows.firstIndex(where: { $0.pane.leaves.contains(leaf) }), !rows[index].pane.leaves.contains(session) else { return false }
        rows[index].pane = rows[index].pane.splitting(leaf, with: .session(session), direction: direction)
        let row = rows[index].identifier
        rows.removeAll { $0.identifier != row && $0.pane == .session(session) }
        if selectedRow == session { selectedRow = row }
        return true
    }

    /// Keeps the share of the first half of a split of a row, after the
    /// user moved its divider. `leaf` starts the second half of the split.
    public mutating func setFraction(_ fraction: Double, ofSplitBefore leaf: UUID, inRow row: UUID) {
        guard let index = rows.firstIndex(where: { $0.identifier == row }) else { return }
        rows[index].pane = rows[index].pane.settingFraction(fraction, ofSplitBefore: leaf)
    }
}
