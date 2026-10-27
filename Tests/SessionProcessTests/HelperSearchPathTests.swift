import Foundation
@testable import SessionProcess
import SessionProcessHarness
import Testing

@Suite struct HelperSearchPathTests {
    @Test func aProgramInAnAppBundleHasTheHelpersFolderOfTheBundle() {
        #expect(HelperSearchPath.helperFolder(forExecutableAt: "/Applications/OpenRun.app/Contents/MacOS/openrun-session")
            == "/Applications/OpenRun.app/Contents/Helpers")
    }

    @Test(arguments: [
        "/Users/someone/openrun/.build/debug/openrun-session",
        "/Users/someone/Contents/MacOS/openrun-session",
        "/Applications/OpenRun.app/Contents/Helpers/openrun",
        "openrun-session",
    ])
    func aProgramOutsideAnAppBundleHasNoHelpersFolder(path: String) {
        #expect(HelperSearchPath.helperFolder(forExecutableAt: path) == nil)
    }

    @Test func theHelpersFolderComesFirstOnThePathOfASession() {
        let helpers = HelperSearchPath(executablePath: "/Applications/OpenRun.app/Contents/MacOS/openrun-session")
        let folder = "/Applications/OpenRun.app/Contents/Helpers"
        #expect(helpers.adding(to: ["PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/someone"])
            == ["PATH": "\(folder):/opt/homebrew/bin:/usr/bin", "HOME": "/Users/someone"])
        #expect(helpers.adding(to: [:]) == ["PATH": "\(folder):/usr/bin:/bin:/usr/sbin:/sbin"])
        #expect(helpers.adding(to: ["PATH": ""]) == ["PATH": folder])
        // A session that a session started has the folder already.
        #expect(helpers.adding(to: ["PATH": "/usr/bin:\(folder)"]) == ["PATH": "/usr/bin:\(folder)"])
    }

    @Test func outsideABundleThePathStaysAsItIs() {
        let helpers = HelperSearchPath(executablePath: "/Users/someone/openrun/.build/debug/openrun-session")
        #expect(helpers.adding(to: ["PATH": "/usr/bin"]) == ["PATH": "/usr/bin"])
    }
}

extension SessionProcessIntegration {
    /// The program of `swift build` runs once from its own folder, and once
    /// as a copy in the folder layout of an app bundle. Only the copy puts
    /// a Helpers folder first on the `PATH` of a session.
    @Suite struct HelperSearchPathOfASessionTests {
        static let script = #"case "$PATH" in */Layout.app/Contents/Helpers:/usr/bin:/bin) echo helpers-first ;; /usr/bin:/bin) echo path-unchanged ;; *) echo "other: $PATH" ;; esac; exec sleep 300"#

        @Test(arguments: [true, false])
        func theHelpersFolderIsFirstOnThePathOnlyInABundle(runsInABundle: Bool) async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            var executable = RunningSessionProcess.sessionExecutable
            if runsInABundle {
                let programs = folder.appendingPathComponent("Layout.app/Contents/MacOS", isDirectory: true)
                try FileManager.default.createDirectory(at: programs, withIntermediateDirectories: true)
                executable = programs.appendingPathComponent("openrun-session")
                try FileManager.default.copyItem(at: RunningSessionProcess.sessionExecutable, to: executable)
            }
            let socketPath = folder.appendingPathComponent("socket").path
            let process = try SocketSecurityHarness.StartedSessionProcess(
                executable: executable, arguments: ["--socket", socketPath], folder: folder, logFile: folder.appendingPathComponent("log")
            )
            defer { process.stop() }
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            let created = try RunningSessionProcess.runOpenrun(
                ["new", "--socket", socketPath, "--", "/bin/sh", "-c", Self.script], environment: ["PATH": "/usr/bin:/bin"], in: folder
            )
            try #require(created.status == 0, "\(created.standardError)")
            let identifier = created.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let expected = runsInABundle ? "helpers-first" : "path-unchanged"
            var screen = ""
            let found = await eventually {
                screen = (try? RunningSessionProcess.runOpenrun(["read", identifier, "--socket", socketPath], in: folder))?.standardOutput ?? ""
                return screen.contains(expected)
            }
            #expect(found, "screen: \(screen)")
        }
    }
}
