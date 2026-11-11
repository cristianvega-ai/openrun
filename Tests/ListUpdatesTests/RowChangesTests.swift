import Foundation
import Testing
@testable import ListUpdates

@Suite struct RowChangesTests {
    @Test func identicalListsHaveNoChanges() {
        #expect(RowChanges(from: [1, 2, 3], to: [1, 2, 3]) { $0 }.isEmpty)
    }
}
