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
}
