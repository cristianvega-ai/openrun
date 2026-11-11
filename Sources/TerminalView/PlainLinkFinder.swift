import Foundation
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

    /// - Parameter rows: The rows of one line that soft wraps join, from the top. When
    ///   the line goes on above the first row or below the last, outside the viewport
    ///   or past the limit of rows, an address that reaches that end is no link,
    ///   because a part of an address can open another page.
    static func link(in rows: [ViewportRowText], firstRow: Int, at cell: (column: Int, row: Int)) -> PlainLink? {
        let isCutAbove = rows.first?.continuesPreviousRow ?? false, isCutBelow = rows.last?.wrapsToNextRow ?? false
        var characters: [Character] = [], places: [(row: Int, columns: Range<Int>)] = []
        for (offset, row) in rows.enumerated() {
            for (column, text) in row.cells.enumerated() {
                let width = column < row.widths.count ? row.widths[column] : .narrow
                // The second cell of a wide character belongs to it. The empty last cell of a row
                // whose wide character went on to the next row belongs to nothing, and is skipped.
                if width == .wideTail, let last = places.last, last.row == firstRow + offset, last.columns.upperBound == column {
                    places[places.count - 1].columns = last.columns.lowerBound..<column + 1
                    continue
                }
                if width == .wideHead { continue }
                // A blank cell ends an address. A hidden format character, such as a zero-width
                // space, joins the cell before it; it stays in the word, so the word is no link.
                let isFormat = text.unicodeScalars.contains { $0.properties.generalCategory == .format }
                characters.append(isFormat ? PlainLinkFinder.format : text.count == 1 ? Character(text) : " ")
                places.append((firstRow + offset, column..<column + 1))
            }
        }
        guard let target = places.firstIndex(where: { $0.row == cell.row && $0.columns.contains(cell.column) }),
            !isDelimiter(characters[target]) else { return nil }
        var start = target, end = target + 1
        while start > 0, !isDelimiter(characters[start - 1]) { start -= 1 }
        while end < characters.count, !isDelimiter(characters[end]) { end += 1 }
        guard !(isCutAbove && start == 0), !(isCutBelow && end == characters.count) else { return nil }
        let word = Array(characters[start..<end])
        // The last scheme that starts at or before the cell, so `(see https://a.b)` gives the address only.
        let schemeStarts = word.indices.filter { index in
            ["http://", "https://"].contains { String(word[index...].prefix($0.count)).lowercased() == $0 }
        }
        guard let schemeStart = schemeStarts.last(where: { start + $0 <= target }) else { return nil }
        var address = Array(word[schemeStart...])
        trimTrailingPunctuation(&address)
        let first = start + schemeStart, after = first + address.count
        guard target < after, !address.contains(PlainLinkFinder.format), let authority = PlainLinkAuthority.read(address),
            !authority.endsAddress || PlainLinkAuthority.endsHost(next: characters.dropFirst(after).first, afterNext: characters.dropFirst(after + 1).first)
        else { return nil }
        // Foundation encodes the letters outside ASCII in the path. It also folds some look-alike
        // forms into ASCII, so a host that differs from the text on the screen is no link.
        guard let url = URL(string: String(address)), url.host?.lowercased() == authority.host.lowercased(),
            LinkSchemeRule.target(for: url.absoluteString) != nil else { return nil }
        let encoded = url.absoluteString
        let covered = places[first..<first + address.count]
        let runs = Dictionary(grouping: covered, by: \.row).keys.sorted().map { row in
            let columns = covered.filter { $0.row == row }.map(\.columns)
            return ViewportCellRun(row: row, columns: columns.map(\.lowerBound).min()!..<columns.map(\.upperBound).max()!)
        }
        return PlainLink(address: encoded, runs: runs)
    }

    /// Stands for a cell that holds a format character, which no address may hold.
    private static let format: Character = "\u{200B}"

    /// No address holds white space or these ASCII characters. Outside ASCII, an
    /// address holds letters and digits, and a symbol such as an emoji, or
    /// punctuation such as `。` or `）`, ends it.
    private static func isDelimiter(_ character: Character) -> Bool {
        if character == format { return false }
        if !character.isASCII { return !(character.isLetter || character.isNumber) }
        return character.isWhitespace || "<>\"`{}|\\^".contains(character)
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
