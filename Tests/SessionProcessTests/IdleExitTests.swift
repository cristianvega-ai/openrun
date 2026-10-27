import Foundation
@testable import SessionProcess
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The launch agent ends itself after a time with no session and no
    /// client. The tests set a short time through the setting for tests.
    @Suite struct IdleExitTests {
        static let setting = "OPENRUN_TEST_IDLE_EXIT_MILLISECONDS"

        @Test func theSettingForTestsShortensTheTimeLimitOfThirtySeconds() {
            #expect(IdleExit(environment: [:]).timeLimit == .seconds(30))
            #expect(IdleExit(environment: [Self.setting: "300"]).timeLimit == .milliseconds(300))
            for refused in ["", "0", "-5", "soon", "3600001", "99999999999999999999"] {
                #expect(IdleExit(environment: [Self.setting: refused]).timeLimit == .seconds(30), "\(refused)")
            }
        }
    }
}
