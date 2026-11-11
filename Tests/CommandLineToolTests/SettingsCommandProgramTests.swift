import Foundation
import SessionProcessHarness
import Testing

extension CommandLineToolIntegration {
    /// `openrun settings`, and who may change a protected setting.
    @Suite struct SettingsCommandProgramTests {
        private static let protectedMessage = "openrun: The setting session-limit is protected. Change it in the settings window of OpenRun.\n"

        @Test func listGetAndSetASetting() async throws {
            try await RunningSessionProcess.run { process in
                let listed = try process.runCommand(["settings", "list"])
                #expect(listed.outputLines.contains("font-size\t13") && listed.outputLines.contains("session-limit\t100\tprotected"))
                let changed = try process.runCommand(["settings", "set", "font-name", "JetBrains", "Mono"])
                #expect(changed.status == 0 && changed.standardOutput.isEmpty && changed.standardError.isEmpty)
                #expect(try process.runCommand(["settings", "get", "font-name"]).standardOutput == "JetBrains Mono\n")
                // The name is quoted by the session process, and the tool adds no second escape.
                let unknown = try process.runCommand(["settings", "set", "colour\u{1B}\\", "red"])
                #expect(unknown.status == 1 && unknown.standardError.hasPrefix(#"openrun: OpenRun has no setting "colour\u{1B}\\". Run"#))
                let unread = try process.runCommand(["settings", "get", "colour\u{1B}"])
                #expect(unread.status == 1 && unread.standardError.hasPrefix(#"openrun: OpenRun has no setting "colour\u{1B}". Run"#))
                let invalid = try process.runCommand(["settings", "set", "font-size", "huge"])
                #expect(invalid.standardError == "openrun: The setting font-size takes a whole number from 6 to 72.\n")
                #expect(try process.runCommand(["settings", "set", "session-limit", "5"]).standardError == Self.protectedMessage)
            }
        }

        /// The tool meets the requirement here. Outside every session it may
        /// change a protected setting, and inside a session it may not.
        @Test func aProtectedSettingChangesOnlyOutsideEverySession() async throws {
            let requirement = "cdhash H\"\(try AdHocBundle.codeHash(of: RunningSessionProcess.commandExecutable))\""
            try await RunningSessionProcess.run(arguments: ["--answerer-requirement", requirement]) { process in
                #expect(try process.runCommand(["settings", "set", "session-limit", "5"]).status == 0)
                let output = process.directory.appendingPathComponent("inside")
                let script = #""$0" --socket "$1" settings set session-limit 7 > "$2" 2>&1; echo "status $?" >> "$2"; exec sleep 60"#
                _ = try process.createSession(program: ["/bin/sh", "-c", script, RunningSessionProcess.commandExecutable.path, process.socketPath, output.path])
                #expect(await eventually { (try? String(contentsOf: output, encoding: .utf8))?.contains("status") == true })
                #expect(try String(contentsOf: output, encoding: .utf8) == Self.protectedMessage + "status 1\n")
                #expect(try process.runCommand(["settings", "get", "session-limit"]).standardOutput == "5\n")
            }
        }

        /// An ad hoc build: the main program of the app bundle that holds the
        /// session process may change a protected setting. Another copy of
        /// the same tool, outside the bundle, may not.
        @Test func theMainProgramOfAnAdHocBundleChangesAProtectedSetting() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let bundle = try AdHocBundle.make(named: "OpenRun", in: folder, mainProgram: RunningSessionProcess.commandExecutable)
            let programs = bundle.appendingPathComponent("Contents/MacOS")
            let process = try RunningSessionProcess(directory: folder, executable: programs.appendingPathComponent("openrun-session"))
            defer { process.stop() }
            let arguments = ["--socket", process.socketPath, "settings", "set", "session-limit", "5"]
            let allowed = try RunningSessionProcess.runOpenrun(arguments, in: folder, executable: programs.appendingPathComponent("OpenRun"))
            #expect(allowed.status == 0 && allowed.standardError.isEmpty)
            #expect(try process.runCommand(["settings", "set", "session-limit", "6"]).standardError == Self.protectedMessage)
            #expect(try process.runCommand(["settings", "get", "session-limit"]).standardOutput == "5\n")
        }
    }
}
