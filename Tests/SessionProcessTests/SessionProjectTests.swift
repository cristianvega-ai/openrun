import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The project of a session (decision of 2026-11-10).
    @Suite struct SessionProjectTests {
        private static func add(_ folder: URL, to process: RunningSessionProcess) throws -> UUID? {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard case .projectAdded(let project) = try answer(to: .addProject(folder: folder.path, name: nil, currentFolder: nil), from: process) else { return nil }
            return project.identifier
        }

        private static func project(of identifier: String, in process: RunningSessionProcess) throws -> UUID? {
            try listedSummaries(of: process).first { $0.identifierText == identifier }?.projectIdentifier
        }

        /// The deepest project wins, and a start folder through a symbolic
        /// link belongs to the project of the real folder. The folder of
        /// the test is under `/var`, itself a link to `/private/var`.
        @Test func aSessionBelongsToTheDeepestProjectOfItsRealStartFolder() async throws {
            try await RunningSessionProcess.run { process in
                let work = process.directory.appendingPathComponent("work")
                let app = work.appendingPathComponent("app")
                let (workProject, appProject) = (try Self.add(work, to: process), try Self.add(app, to: process))
                try FileManager.default.createDirectory(at: app.appendingPathComponent("source"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: process.directory.appendingPathComponent("application"), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(atPath: process.directory.appendingPathComponent("link").path, withDestinationPath: "work/app")
                let cases: [(String, UUID?)] = [
                    ("work/app/source", appProject), ("work", workProject), ("link", appProject), ("application", nil),
                ]
                for (folder, expected) in cases {
                    let identifier = try process.createSession(program: ["/bin/sleep", "60"], folder: process.directory.appendingPathComponent(folder))
                    #expect(try Self.project(of: identifier, in: process) == expected, "\(folder)")
                }
            }
        }

        @Test func aChangeOfTheProjectsChangesTheSessionsThatRun() async throws {
            try await RunningSessionProcess.run { process in
                let folder = process.directory.appendingPathComponent("work")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let identifier = try process.createSession(program: ["/bin/sleep", "60"], folder: folder)
                let watcher = try SessionChangeWatcher(process)
                #expect(watcher.initialList.first?.projectIdentifier == nil)
                let project = try #require(try Self.add(folder, to: process))
                #expect(watcher.summary(of: identifier) { $0.projectIdentifier == project } != nil)
                #expect(try Self.project(of: identifier, in: process) == project)
                #expect(try answer(to: .removeProject(identifier: project), from: process) == .acknowledged)
                #expect(watcher.summary(of: identifier) { $0.projectIdentifier == nil } != nil)
            }
        }
    }
}
