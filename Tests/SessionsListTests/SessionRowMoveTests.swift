import Foundation
import Testing
@testable import SessionsList

@Suite struct SessionRowMoveTests {
    private let rows = (0..<5).map { _ in UUID() }

    private func moved(_ move: SessionRowMove?) -> [Int] {
        guard let move else { return [] }
        var order = rows
        order.remove(at: order.firstIndex(of: move.identifier)!)
        order.insert(move.identifier, at: move.destination)
        return order.map { rows.firstIndex(of: $0)! }
    }

    @Test func aRowMovesInTheFullList() {
        #expect(moved(SessionRowMove(order: rows, visible: rows, row: 0, dropRow: 3)) == [1, 2, 0, 3, 4])
        #expect(moved(SessionRowMove(order: rows, visible: rows, row: 4, dropRow: 0)) == [4, 0, 1, 2, 3])
        #expect(moved(SessionRowMove(order: rows, visible: rows, row: 1, dropRow: 9)) == [0, 2, 3, 4, 1])
        #expect(SessionRowMove(order: rows, visible: rows, row: 2, dropRow: 2) == nil)
        #expect(SessionRowMove(order: rows, visible: rows, row: 2, dropRow: 3) == nil)
    }

    /// Rows 1 and 3 are hidden. They stay where they are.
    @Test func hiddenRowsKeepTheirPlaces() {
        let visible = [rows[0], rows[2], rows[4]]
        #expect(moved(SessionRowMove(order: rows, visible: visible, row: 0, dropRow: 2)) == [1, 2, 3, 0, 4])
        #expect(moved(SessionRowMove(order: rows, visible: visible, row: 2, dropRow: 0)) == [4, 0, 1, 2, 3])
        #expect(moved(SessionRowMove(order: rows, visible: visible, row: 0, dropRow: 3)) == [1, 2, 3, 4, 0])
        #expect(SessionRowMove(order: rows, visible: [rows[1]], row: 0, dropRow: 1) == nil)
    }
}
