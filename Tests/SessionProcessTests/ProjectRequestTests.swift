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
                    "claude-code-model", "claude-code-permission-mode", "claude-code-program", "agent-process-limit",
                    "claude-code-accounts", "codex-accounts",
                ])
                #expect(settings.filter(\.isProtected).map(\.name) == [
                    "session-limit", "ask-before-unsafe-paste", "claude-code-permission-mode", "claude-code-program", "agent-process-limit",
                    "claude-code-accounts", "codex-accounts",
                ])
                #expect(settings.first { $0.name == "session-limit" }?.text == "100")
                // Nothing was written: a process that changed nothing leaves no file.
                #expect(!FileManager.default.fileExists(atPath: process.directory.appendingPathComponent("settings.json").path))
            }
        }

        /// The message of a failure, or nil for another answer.
        private static func failureMessage(_ answer: ServerMessage?) -> String? {
            guard case .failure(let failure) = answer, failure.reason == .invalidRequest else { return nil }
            return failure.message
        }

        @Test func eachRequestChangesTheList() async throws {
            try await RunningSessionProcess.run { process in
                let real = try #require(realpath(process.directory.path, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) })
                for name in ["app", "tool"] {
                    try FileManager.default.createDirectory(at: process.directory.appendingPathComponent(name), withIntermediateDirectories: false)
                }
                try FileManager.default.createSymbolicLink(atPath: process.directory.appendingPathComponent("link").path, withDestinationPath: "tool")
                guard case .projectAdded(let app) = try answer(to: .addProject(folder: process.directory.path + "/app/.", name: " App ", currentFolder: nil), from: process),
                      case .projectAdded(let tool) = try answer(to: .addProject(folder: "link", name: nil, currentFolder: process.directory.path), from: process) else {
                    Issue.record("The session process added no project.")
                    return
                }
                // The folder is absolute and standard, with its links resolved.
                #expect(app.folder == real + "/app" && app.name == "App")
                #expect(tool.folder == real + "/tool" && tool.name == nil)
                #expect(try answer(to: .moveProject(identifier: tool.identifier, place: 0), from: process) == .acknowledged)
                #expect(try answer(to: .renameProject(identifier: tool.identifier, name: "Tool"), from: process) == .acknowledged)
                #expect(try answer(to: .renameProject(identifier: app.identifier, name: ""), from: process) == .acknowledged)
                var renamed = tool
                renamed.name = "Tool"
                let unnamed = ProjectSummary(identifier: app.identifier, name: nil, folder: app.folder)
                #expect(try answer(to: .listProjects, from: process) == .projectList([renamed, unnamed]))
                #expect(try answer(to: .removeProject(identifier: tool.identifier), from: process) == .acknowledged)
                #expect(try answer(to: .listProjects, from: process) == .projectList([unnamed]))
            }
        }

        @Test func eachRefusalSaysWhyAndChangesNothing() async throws {
            try await RunningSessionProcess.run { process in
                let folder = process.directory.path
                guard case .projectAdded(let project) = try answer(to: .addProject(folder: folder, name: nil, currentFolder: nil), from: process) else {
                    Issue.record("The session process added no project.")
                    return
                }
                let unknown = UUID()
                let refusals: [(ClientMessage, String)] = [
                    (.addProject(folder: folder + "/./", name: nil, currentFolder: nil), "is already a project"),
                    (.addProject(folder: folder + "/missing\u{1B}[2J", name: nil, currentFolder: nil), #"/missing\u{1B}[2J" does not exist"#),
                    (.addProject(folder: process.directory.appendingPathComponent("log").path, name: nil, currentFolder: nil), "is not a folder"),
                    (.addProject(folder: "relative", name: nil, currentFolder: nil), "no current folder was given"),
                    (.addProject(folder: "/", name: "two\nlines", currentFolder: nil), "no control characters"),
                    (.renameProject(identifier: unknown, name: "x"), "No project has the identifier \(unknown.uuidString)"),
                    (.removeProject(identifier: unknown), "No project has the identifier"),
                    (.moveProject(identifier: project.identifier, place: 1), "The place 1 is outside the list of 1 projects."),
                ]
                for (request, expected) in refusals {
                    let message = Self.failureMessage(try answer(to: request, from: process))
                    #expect(message?.contains(expected) == true, "\(request.self): \(String(describing: message))")
                }
                #expect(try answer(to: .listProjects, from: process) == .projectList([project]))
            }
        }
    }
}
