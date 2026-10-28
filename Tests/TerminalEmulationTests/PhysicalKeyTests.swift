import Testing
@testable import TerminalEmulation

@Suite struct PhysicalKeyTests {
    @Test func everyPhysicalKeyHasItsOwnNumber() {
        let numbers = PhysicalKey.allCases.map { $0.raw.rawValue }
        #expect(Set(numbers).count == PhysicalKey.allCases.count)
    }

    @Test func theUnidentifiedKeyIsTheFirstNumber() {
        #expect(PhysicalKey.unidentified.raw.rawValue == 0)
    }
}
