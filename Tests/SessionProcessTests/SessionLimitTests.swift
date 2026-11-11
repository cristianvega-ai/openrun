import Foundation
import SessionProtocol
import Testing
@testable import SessionProcess

@Suite struct SessionLimitTests {
    /// A registry with a small limit stands for the limit of 100, so the
    /// test starts three programs and not a hundred.
    @Test func aSessionPastTheLimitIsRefusedWithAMessageThatNamesIt() async throws {
        let registry = SessionRegistry(socketPath: "/nonexistent/socket", helperSearchPath: HelperSearchPath(executablePath: nil), sessionLimit: 2)
        let size = SessionSize(columns: 80, rows: 24)
        let first = try await registry.create(folder: "/", command: ["/bin/sleep", "60"], size: size, environment: [:])
        _ = try await registry.create(folder: "/", command: ["/bin/sleep", "60"], size: size, environment: [:])
        await #expect(throws: SessionProcessError.sessionLimitReached(limit: 2)) {
            try await registry.create(folder: "/", command: ["/bin/sleep", "60"], size: size, environment: [:])
        }
        // An ended session makes room.
        await registry.session(for: first.identifier)?.terminate()
        _ = try await registry.create(folder: "/", command: ["/bin/sleep", "60"], size: size, environment: [:])
        await registry.terminateAll()
    }

    @Test func theLimitIsOneHundred() {
        #expect(SessionRegistry.defaultSessionLimit == 100)
        #expect(SessionProcessError.sessionLimitReached(limit: 100).description.contains("100 sessions, its limit"))
    }
}
