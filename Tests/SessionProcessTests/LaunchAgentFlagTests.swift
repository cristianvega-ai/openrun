import Foundation
import SessionProcessHarness
import Testing

extension SessionProcessIntegration {
    /// A test cannot register a launch agent. So these tests start
    /// `openrun-session --launch-agent` by hand, with a Mach service name
    /// that launchd does not know, on a socket of the test.
    @Suite struct LaunchAgentFlagTests {
        static let testMachServiceSetting = "OPENRUN_TEST_WAKE_SERVICE_NAME"

        static func start(in folder: URL, environment: [String: String] = [:]) throws -> SocketSecurityHarness.StartedSessionProcess {
            let unknownService = "ai.cristianvega.openrun.test.\(UUID().uuidString)"
            return try SocketSecurityHarness.StartedSessionProcess(
                arguments: ["--launch-agent", "--socket", folder.appendingPathComponent("socket").path],
                folder: folder,
                logFile: folder.appendingPathComponent("log"),
                environment: environment.merging([testMachServiceSetting: unknownService]) { ours, _ in ours }
            )
        }

        @Test func aLaunchAgentWhoseWakeServiceCannotStartStillServesItsSocket() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let process = try Self.start(in: folder)
            defer { process.stop() }
            #expect(await process.waitForLog(containing: "The wake service did not start"), "log: \(process.log)")
            let list = try RunningSessionProcess.runOpenrun(["list", "--socket", folder.appendingPathComponent("socket").path], in: folder)
            #expect(list.status == 0, "\(list.standardError)")
        }
    }
}
