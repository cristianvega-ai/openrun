import Darwin
import Testing
@testable import PseudoTerminal

@Suite struct TerminalSessionCensusTests {
    /// This process lives, so its terminal session does. A number that no
    /// process has as its terminal session is not live.
    @Test func aSessionIsLiveWhileOneOfItsProcessesLives() throws {
        let own = getsid(0)
        let live = try #require(TerminalSessionCensus.liveSessions(among: [own, Int32.max]))
        #expect(live == [own])
        #expect(TerminalSessionCensus.liveSessions(among: []) == [])
    }
}
