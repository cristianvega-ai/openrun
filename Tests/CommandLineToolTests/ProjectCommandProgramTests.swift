import Foundation
import SessionProcessHarness
import Testing

extension CommandLineToolIntegration {
    /// `openrun project` with names and folders that a hostile client chose.
    @Suite struct ProjectCommandProgramTests {
        private static func holdsControlCharacter(_ text: String) -> Bool {
            text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" && $0 != "\t" || (0x7F...0x9F).contains($0.value) }
        }

        @Test func aHostileFolderIsOneEscapedLineAndExactJSON() async throws {
            try await RunningSessionProcess.run { process in
                let hostile = "evil\u{1B}[31m\nfake\tcolumn\\"
                try FileManager.default.createDirectory(at: process.directory.appendingPathComponent(hostile), withIntermediateDirectories: false)
                let added = try process.runCommand(["project", "add", hostile])
                #expect(added.status == 0 && added.standardError.isEmpty)
                let identifier = try #require(added.outputLines.first)
                let listed = try process.runCommand(["project", "list"])
                #expect(listed.status == 0 && !Self.holdsControlCharacter(listed.standardOutput))
                #expect(listed.outputLines.count == 1)
                let columns = listed.standardOutput.dropLast().split(separator: "\t", omittingEmptySubsequences: false)
                #expect(columns.count == 3 && columns.first == Substring(identifier))
                #expect(columns.dropFirst().first == "evil\\u{1B}[31m\\nfake\\tcolumn\\\\")
                #expect(columns.last?.hasSuffix("/evil\\u{1B}[31m\\nfake\\tcolumn\\\\") == true)
                // JSON escapes every control character, so it gives the folder exactly.
                let json = try process.runCommand(["project", "list", "--json"])
                let document = try #require(JSONSerialization.jsonObject(with: Data(json.standardOutput.utf8)) as? [String: [[String: Any]]])
                #expect((document["projects"]?.first?["folder"] as? String)?.hasSuffix("/" + hostile) == true)
            }
        }

        @Test func aProjectIsRenamedAndRemovedByItsFolderOrItsIdentifier() async throws {
            try await RunningSessionProcess.run { process in
                try FileManager.default.createDirectory(at: process.directory.appendingPathComponent("app"), withIntermediateDirectories: false)
                let identifier = try #require(try process.runCommand(["project", "add", "app", "--name", "App"]).outputLines.first)
                #expect(try process.runCommand(["project", "rename", "./app", "My", "App"]).status == 0)
                #expect(try process.runCommand(["project", "list"]).outputLines.first?.split(separator: "\t").dropFirst().first == "My App")
                let removed = try process.runCommand(["project", "remove", String(identifier.prefix(8))])
                #expect(removed.status == 0 && removed.standardOutput.isEmpty && removed.standardError.isEmpty)
                #expect(try process.runCommand(["project", "list"]).standardOutput.isEmpty)
            }
        }

        /// The messages of the session process quote the text of a client.
        /// The tool prints them with no second escape, so a backslash shows
        /// once, and no control character reaches the terminal.
        @Test func aRefusalShowsTheClientTextEscapedOnce() async throws {
            try await RunningSessionProcess.run { process in
                let missing = try process.runCommand(["project", "add", "gone\u{1B}[2J\\x"])
                #expect(missing.status == 1 && !Self.holdsControlCharacter(missing.standardError))
                #expect(missing.standardError.hasSuffix(#"/gone\u{1B}[2J\\x" does not exist."# + "\n"))
                try FileManager.default.createDirectory(at: process.directory.appendingPathComponent("app"), withIntermediateDirectories: false)
                #expect(try process.runCommand(["project", "add", "app"]).status == 0)
                let named = try process.runCommand(["project", "rename", "app", "bad\u{7}name"])
                #expect(named.standardError == "openrun: A project name has at most 100 characters and no control characters.\n")
                let unknown = try process.runCommand(["project", "remove", "nothing\u{1B}"])
                #expect(unknown.status == 1 && unknown.standardError.contains(#"starts with nothing\u{1B}, or"#))
            }
        }
    }
}
