import Foundation
import SessionProcessHarness
import Testing

extension CommandLineToolIntegration {
    /// `openrun list --json`, the shape that agents parse.
    @Suite struct ListAsJSONTests {
        private static let keys: Set<String> = [
            "identifier", "name", "title", "folder", "currentFolder", "branch", "command", "foregroundProgram",
            "isInProgress", "alert", "size", "createdAt", "lastOutputAt", "lastInputAt", "projectIdentifier",
        ]

        private static func sessions(of process: RunningSessionProcess) throws -> [[String: Any]] {
            let result = try process.runCommand(["list", "--json"])
            #expect(result.status == 0 && result.standardError.isEmpty)
            let document = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
            return try #require(document["sessions"] as? [[String: Any]])
        }

        @Test func everySessionHasEveryKey() async throws {
            try await RunningSessionProcess.run { process in
                #expect(try Self.sessions(of: process).isEmpty)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", #"printf '\033]2;Tests\007\033]9;Done\007'; exec sleep 60"#])
                #expect(await eventually { (try? Self.sessions(of: process).first?["alert"] as? [String: Any]) != nil })
                let session = try #require(try Self.sessions(of: process).first)
                #expect(Set(session.keys) == Self.keys)
                #expect(session["identifier"] as? String == identifier)
                #expect(session["title"] as? String == "Tests")
                #expect(session["name"] is NSNull && session["projectIdentifier"] is NSNull)
                #expect(session["command"] as? [String] == ["/bin/sh", "-c", #"printf '\033]2;Tests\007\033]9;Done\007'; exec sleep 60"#])
                let alert = try #require(session["alert"] as? [String: Any])
                #expect(alert["text"] as? String == "Done" && alert["source"] as? String == "terminalNotification")
                // A time is text in ISO 8601.
                let createdAt = try #require(session["createdAt"] as? String)
                #expect(ISO8601DateFormatter().date(from: createdAt) != nil)
                #expect((session["size"] as? [String: Int]) == ["columns": 80, "rows": 24])
            }
        }

        /// The project of a session is its identifier, in lower case as
        /// `openrun project add` prints it.
        @Test func aSessionInAProjectNamesTheProject() async throws {
            try await RunningSessionProcess.run { process in
                let folder = process.directory.appendingPathComponent("app")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let added = try process.runCommand(["project", "add", "app"])
                #expect(added.status == 0 && added.standardError.isEmpty)
                _ = try process.createSession(program: ["/bin/sh", "-c", "sleep 60"], folder: folder.appendingPathComponent("."))
                let session = try #require(try Self.sessions(of: process).first)
                #expect(session["projectIdentifier"] as? String == added.outputLines.first)
            }
        }
    }
}
