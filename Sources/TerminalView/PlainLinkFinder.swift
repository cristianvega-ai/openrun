import TerminalEmulation
import TerminalRendering

/// Finds a plain `http` or `https` address under a cell (decision of
/// 2026-11-10). It reads only the row of the cell and the rows that a soft wrap
/// joins to it, and only when the view asks, so no frame scans the screen.
enum PlainLinkFinder {
    /// A soft-wrapped line longer than this many rows on each side is cut, which
    /// keeps the work of one search small.
    static let rowLimit = 32

    static func link(at cell: ViewportCell, in terminal: Terminal) -> PlainLink? {
        guard let middle = terminal.viewportRowText(at: cell.row) else { return nil }
        var rows = [middle], first = Int(cell.row)
        while rows[0].continuesPreviousRow, first > 0, rows.count <= rowLimit,
            let above = terminal.viewportRowText(at: UInt32(first - 1)), above.wrapsToNextRow {
            rows.insert(above, at: 0)
            first -= 1
        }
        while let last = rows.last, last.wrapsToNextRow, rows.count <= 2 * rowLimit,
            let below = terminal.viewportRowText(at: UInt32(first + rows.count)) {
            rows.append(below)
        }
        return link(in: rows, firstRow: first, at: (Int(cell.column), Int(cell.row)))
    }

    /// - Parameter rows: The rows of one line that soft wraps join, from the top.
    static func link(in rows: [ViewportRowText], firstRow: Int, at cell: (column: Int, row: Int)) -> PlainLink? {
        var characters: [Character] = [], places: [(row: Int, column: Int)] = []
        for (offset, row) in rows.enumerated() {
            for (column, text) in row.cells.enumerated() {
                // A blank cell and the second cell of a wide character end an address.
                characters.append(text.count == 1 ? Character(text) : " ")
                places.append((firstRow + offset, column))
            }
        }
        guard let target = places.firstIndex(where: { $0.row == cell.row && $0.column == cell.column }), !isDelimiter(characters[target]) else { return nil }
        var start = target, end = target + 1
        while start > 0, !isDelimiter(characters[start - 1]) { start -= 1 }
        while end < characters.count, !isDelimiter(characters[end]) { end += 1 }
        let word = Array(characters[start..<end])
        // The last scheme that starts at or before the cell, so `(see https://a.b)` gives the address only.
        let schemeStarts = word.indices.filter { index in
            ["http://", "https://"].contains { String(word[index...].prefix($0.count)).lowercased() == $0 }
        }
        guard let schemeStart = schemeStarts.last(where: { start + $0 <= target }) else { return nil }
        var address = Array(word[schemeStart...])
        trimTrailingPunctuation(&address)
        let first = start + schemeStart
        guard target < first + address.count, LinkSchemeRule.target(for: String(address)) != nil else { return nil }
        let covered = places[first..<first + address.count]
        let runs = Dictionary(grouping: covered, by: \.row).keys.sorted().map { row in
            let columns = covered.filter { $0.row == row }.map(\.column)
            return ViewportCellRun(row: row, columns: columns.min()!..<columns.max()! + 1)
        }
        return PlainLink(address: String(address), runs: runs)
    }

    /// An address that a program prints is ASCII, as `URL` wants it, so any other
    /// character, such as a wide character after it, ends the address.
    private static func isDelimiter(_ character: Character) -> Bool {
        !character.isASCII || character.isWhitespace || "<>\"`{}|\\^".contains(character)
    }

    /// Text often ends a sentence or a bracket right after an address. A closing
    /// bracket stays when the address opened it, as in a page of Wikipedia.
    private static func trimTrailingPunctuation(_ address: inout [Character]) {
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        while let last = address.last {
            if ".,;:!?'*".contains(last) {
                address.removeLast()
            } else if let opening = pairs[last], address.filter({ $0 == opening }).count < address.filter({ $0 == last }).count {
                address.removeLast()
            } else {
                return
            }
        }
    }
}
