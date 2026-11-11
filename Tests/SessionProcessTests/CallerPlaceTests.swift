import Darwin
import Foundation
import SessionProtocol
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

    /// A program with no terminal session ended before the check. This
    /// process runs in no session of the registry.
    @Test func theRegistryPlacesEachCaller() async {
        let registry = SessionRegistry(socketPath: "/nowhere", helperSearchPath: .ofThisProcess())
        #expect(await registry.place(of: PeerProcess(processIdentifier: 1, terminalSessionIdentifier: nil, auditToken: Data())) == .unknown)
        #expect(await registry.place(of: PeerProcess(processIdentifier: getpid(), terminalSessionIdentifier: getsid(0), auditToken: Data())) == .outsideEverySession)
    }
}
