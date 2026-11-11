import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The requests of the settings (decision of 2026-11-10).
    @Suite struct SettingRequestTests {
        private static func text(of name: String, in process: RunningSessionProcess) throws -> String? {
            guard case .settingList(let settings) = try answer(to: .listSettings, from: process) else { return nil }
            return settings.first { $0.name == name }?.text
        }

        private static func failureMessage(_ answer: ServerMessage?) -> String? {
            guard case .failure(let failure) = answer, failure.reason == .invalidRequest else { return nil }
            return failure.message
        }

        @Test func anyClientChangesASettingThatIsNotProtected() async throws {
            try await RunningSessionProcess.run { process in
                #expect(try answer(to: .changeSetting(name: "font-size", text: "15"), from: process) == .acknowledged)
                #expect(try Self.text(of: "font-size", in: process) == "15")
                let unknown = Self.failureMessage(try answer(to: .changeSetting(name: "colour\u{1B}", text: "red"), from: process))
                #expect(unknown == #"OpenRun has no setting "colour\u{1B}". Run `openrun settings list` to see the settings."#)
                let invalid = Self.failureMessage(try answer(to: .changeSetting(name: "font-size", text: "huge"), from: process))
                #expect(invalid == "The setting font-size takes a whole number from 6 to 72.")
                #expect(try Self.text(of: "font-size", in: process) == "15")
            }
        }

        /// A program outside every session that does not meet the requirement
        /// of the answerer, such as the tool, may not change a protected setting.
        @Test func anotherProgramGetsTheProtectedMessage() async throws {
            try await RunningSessionProcess.run { process in
                let message = Self.failureMessage(try answer(to: .changeSetting(name: "session-limit", text: "5"), from: process))
                #expect(message == "The setting session-limit is protected. Change it in the settings window of OpenRun.")
                #expect(try Self.text(of: "session-limit", in: process) == "100")
            }
        }

        /// The test process meets the requirement, as OpenRun.app does.
        @Test func theProgramThatAnswersTheQuestionsChangesAProtectedSetting() async throws {
            try await RunningSessionProcess.run(arguments: try testProcessAnswersArguments()) { process in
                let changed = try answer(to: .changeSetting(name: "ask-before-unsafe-paste", text: "off"), from: process)
                #expect(changed == .acknowledged)
                #expect(try Self.text(of: "ask-before-unsafe-paste", in: process) == "off")
            }
        }
    }
}
