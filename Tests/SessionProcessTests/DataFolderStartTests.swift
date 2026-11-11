import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The data folder across a restart, and with files that cannot be read.
    @Suite struct DataFolderStartTests {
        @Test func aRestartKeepsTheProjectsAndTheSettings() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let first = try RunningSessionProcess(directory: folder)
            guard case .projectAdded(let project) = try answer(to: .addProject(folder: folder.path, name: "Work", currentFolder: nil), from: first) else {
                first.stop()
                Issue.record("The session process added no project.")
                return
            }
            let changed = try answer(to: .changeSetting(name: "font-name", text: "Menlo"), from: first)
            first.stop()
            #expect(changed == .acknowledged)
            let second = try RunningSessionProcess(directory: folder, logName: "second-log")
            defer { second.stop() }
            #expect(try answer(to: .listProjects, from: second) == .projectList([project]))
            guard case .settingList(let settings) = try answer(to: .listSettings, from: second) else {
                Issue.record("The session process sent no list of the settings.")
                return
            }
            #expect(settings.first { $0.name == "font-name" }?.text == "Menlo")
        }

        /// A file that cannot be read is set aside and never stops the start.
        @Test func aCorruptFileDoesNotStopTheStart() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            for name in ["projects.json", "project-folders.json", "settings.json"] {
                try Data("{\"format\": 1,".utf8).write(to: folder.appendingPathComponent(name))
            }
            let process = try RunningSessionProcess(directory: folder)
            defer { process.stop() }
            #expect(try answer(to: .listProjects, from: process) == .projectList([]))
            #expect(try answer(to: .changeSetting(name: "theme", text: "paper"), from: process) == .acknowledged)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            for prefix in ["projects.unreadable-", "project-folders.unreadable-", "settings.unreadable-"] {
                #expect(names.contains { $0.hasPrefix(prefix) }, "\(names)")
            }
            #expect(process.log.contains("could not be read and now has the name"), "\(process.log)")
        }
    }
}
