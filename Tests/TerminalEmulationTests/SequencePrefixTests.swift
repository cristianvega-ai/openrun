import Testing
@testable import TerminalEmulation

@Suite struct SequencePrefixTests {
    /// The prefix keeps eight bytes and counts all of them, so a longer
    /// sequence never equals a shorter one.
    @Test func aPrefixTellsSequencesApart() {
        var long = SequencePrefix("27")
        for byte in Array(";1;2;3;4;5;6".utf8) { long.append(byte) }
        #expect(SequencePrefix("27") == SequencePrefix("27") && SequencePrefix("27") != SequencePrefix("24"))
        #expect(long.count == 14 && long != SequencePrefix("27;1;2;3"))
    }

    /// The kind of a mark ends at a semicolon or at the end of the mark.
    @Test func aKindEndsAtASemicolonOrTheEnd() {
        let mark = SequencePrefix("133;A").bytes
        #expect(SequencePrefix("133;A").kind(length: 5) == mark && SequencePrefix("133;A;cl=m").kind(length: 5) == mark)
        #expect(SequencePrefix("133;AB").kind(length: 5) == nil && SequencePrefix("133;").kind(length: 5) == nil)
    }
}
