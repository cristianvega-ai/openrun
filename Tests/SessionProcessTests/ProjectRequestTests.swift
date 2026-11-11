import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The requests of the projects (decision of 2026-11-10).
    @Suite struct ProjectRequestTests {
        @Test func aNewProcessHasNoProjectsAndTheDefaultSettings() async throws {
            try await RunningSessionProcess.run { process in
                #expect(try answer(to: .listProjects, from: process) == .projectList([]))
                guard case .settingList(let settings) = try answer(to: .listSettings, from: process) else {
                    Issue.record("The session process sent no list of the settings.")
                    return
                }
                #expect(settings.map(\.name) == [
                    "theme", "font-name", "font-size", "option-as-alt", "scrollback-limit", "new-session-commands",
                    "open-links-in", "notifications", "session-limit", "ask-before-unsafe-paste",
                ])
                #expect(settings.filter(\.isProtected).map(\.name) == ["session-limit", "ask-before-unsafe-paste"])
                #expect(settings.first { $0.name == "session-limit" }?.text == "100")
                // Nothing was written: a process that changed nothing leaves no file.
                #expect(!FileManager.default.fileExists(atPath: process.directory.appendingPathComponent("settings.json").path))
            }
        }
    }
}
