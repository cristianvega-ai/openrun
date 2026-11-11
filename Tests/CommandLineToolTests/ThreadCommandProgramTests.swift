import Foundation
import SessionProcessHarness
import Testing

extension CommandLineToolIntegration {
    /// `openrun thread`, with the fake agent in place of Claude Code.
    @Suite struct ThreadCommandProgramTests {
        private func listed(_ process: RunningSessionProcess) throws -> [String] {
            try process.runCommand(["thread", "list"]).outputLines
        }

        @Test func aThreadFromItsStartToItsClose() async throws {
            let process = try RunningSessionProcess.withFakeAgent(turns: ["plain-turn", "command-turn"])
            defer { process.stop() }
            let created = try process.runCommand(["thread", "new", "--folder", process.directory.path, "--name", "Notes", "--", "Reply", "with", "ok."])
            #expect(created.status == 0 && created.standardError.isEmpty)
            let thread = created.standardOutput.trimmingCharacters(in: .newlines)
            #expect(await eventually { (try? listed(process).first?.hasPrefix(thread + "\tfinishedTurn\t")) == true })
            #expect(try listed(process).first?.hasSuffix("\tNotes") == true)

            // A unique start of the identifier names the thread.
            let text = try process.runCommand(["thread", "read", String(thread.prefix(8))]).standardOutput
            #expect(text == "You:\nReply with ok.\n\nAgent:\nok\n")
            let events = try process.runCommand(["thread", "read", thread, "--json"]).outputLines
            #expect(events.count > 2 && events.allSatisfy { $0.hasPrefix("{") && $0.hasSuffix("}") })

            #expect(try process.runCommand(["thread", "send", thread, "Again."]).status == 0)
            #expect(await eventually { (try? listed(process).first?.contains("\tinProgress\t")) == false })
            let second = try process.runCommand(["thread", "read", thread]).standardOutput
            #expect(second.hasPrefix(text + "\nYou:\nAgain.\n\nTool Bash (succeeded): {\"command\":\"pwd && ") && second.contains("\n\nAgent:\nI created `notes.txt`"))
            #expect(try process.runCommand(["thread", "rename", thread, "Release", "notes"]).status == 0)
            #expect(try listed(process).first?.hasSuffix("\tRelease notes") == true)
            let json = try process.runCommand(["thread", "list", "--json"]).standardOutput
            #expect(json.contains("\"name\" : \"Release notes\"") && json.contains("\"identifier\" : \"\(thread)\"") && json.contains("\"accountName\" : null"))

            #expect(try process.runCommand(["thread", "stop", thread]).status == 0)
            #expect(try process.runCommand(["thread", "close", thread]).status == 0)
            #expect(try listed(process).isEmpty)
            let missing = try process.runCommand(["thread", "read", thread])
            #expect(missing.status == 1 && missing.standardError == "openrun: No thread has an identifier that starts with \(thread). Run 'openrun thread list' to see the threads.\n")
        }

        @Test func aRequestThatTheSessionProcessRefusesGivesItsReason() async throws {
            let process = try RunningSessionProcess.withFakeAgent()
            defer { process.stop() }
            let missing = try process.runCommand(["thread", "new", "--folder", process.directory.path + "/missing"])
            #expect(missing.status == 1 && missing.standardOutput.isEmpty && missing.standardError.hasPrefix("openrun: "))
            // A program in a session may not use the threads (decision of 2026-11-10).
            let output = process.directory.appendingPathComponent("inside")
            let script = #""$0" --socket "$1" thread list > "$2" 2>&1; echo "status $?" >> "$2"; exec sleep 60"#
            _ = try process.createSession(program: ["/bin/sh", "-c", script, RunningSessionProcess.commandExecutable.path, process.socketPath, output.path])
            #expect(await eventually { (try? String(contentsOf: output, encoding: .utf8))?.contains("status") == true })
            #expect(try String(contentsOf: output, encoding: .utf8) == "openrun: Only a program outside every session and every thread may use the agent threads.\nstatus 1\n")
        }
    }
}
