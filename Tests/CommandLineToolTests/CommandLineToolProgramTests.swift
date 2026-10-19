import Foundation
import SessionProcessHarness
import Testing

extension CommandLineToolIntegration {
    @Suite struct CommandLineToolProgramTests {
        @Test func helpPrintsTheUsageAndExitsWithZero() throws {
            let directory = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let result = try RunningSessionProcess.runOpenrun(["help"], in: directory)
            #expect(result.status == 0)
            #expect(result.standardOutput.contains("Usage: openrun COMMAND"))
            #expect(result.standardError.isEmpty)
        }

        @Test func aUsageErrorGoesToStandardErrorWithExitCodeTwo() throws {
            let directory = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            for arguments in [[], ["bogus"], ["attach"], ["send", "x"]] {
                let result = try RunningSessionProcess.runOpenrun(arguments, in: directory)
                #expect(result.status == 2, "arguments: \(arguments)")
                #expect(result.standardOutput.isEmpty)
                #expect(result.standardError.contains("openrun help"))
            }
        }

    }
}
