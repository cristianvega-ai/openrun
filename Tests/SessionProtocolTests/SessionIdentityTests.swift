import Foundation
import Testing
@testable import SessionProtocol

@Suite struct SessionIdentityTests {
    @Test func identifiersAreLowercase() {
        let identifier = UUID()
        let summary = SessionSummary(identifier: identifier, folder: "/", command: [], size: SessionSize(columns: 1, rows: 1), createdAt: .now)
        #expect(summary.identifierText == identifier.uuidString.lowercased())
    }

    @Test func theEnvironmentNamesTheSessionAndTheSocket() {
        let identifier = UUID()
        let variables = SessionEnvironment.variables(sessionIdentifier: identifier, socketPath: "/run/session.socket")
        #expect(variables == [
            "OPENRUN_SESSION": identifier.uuidString.lowercased(),
            "OPENRUN_SOCKET": "/run/session.socket",
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "OpenRun",
        ])
    }
}
