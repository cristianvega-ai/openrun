import Foundation
import Testing
@testable import SessionProcess

@Suite struct CallerPlaceTests {
    @Test func aCallerActsFreelyOnlyOnItsOwnSessionOrFromOutside() {
        let own = UUID()
        let other = UUID()
        #expect(CallerPlace.session(own).mayAct(on: own))
        #expect(!CallerPlace.session(own).mayAct(on: other))
        #expect(CallerPlace.outsideEverySession.mayAct(on: other))
    }

    /// A program that ended before the check may have run in any session.
    @Test func aCallerWhoseSessionIsUnknownActsOnNoSession() {
        #expect(!CallerPlace.unknown.mayAct(on: UUID()))
    }
}
