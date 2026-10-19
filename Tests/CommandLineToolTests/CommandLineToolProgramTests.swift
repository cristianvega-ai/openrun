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

        /// True when the text holds a control character other than the new
        /// lines and tabs that the output itself uses to shape lines and
        /// columns. Escape and the other C0 controls, DEL, and the C1 controls
        /// all count.
        private static func holdsControlCharacter(_ text: String) -> Bool {
            text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" && $0 != "\t" || (0x7F...0x9F).contains($0.value) }
        }

        private static let escape = "\u{1B}"
        private static let newLine = "\n"
        private static let tab = "\t"

        @Test func listShowsOneLineWithThreeColumnsWhateverTheClientChose() async throws {
            try await RunningSessionProcess.run { process in
                // A folder name and an argument with Escape, new line, and tab,
                // as a hostile client would choose them.
                let hostileName = "evil\(Self.escape)[31m\(Self.newLine)fake line\(Self.tab)fake column"
                let folder = process.directory.appendingPathComponent(hostileName)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let identifier = try process.createSession(
                    program: ["/bin/sh", "-c", "sleep 60", "ARG\u{1B}[31m\nINJECTED\tCOLUMN\\"],
                    folder: folder
                )
                let result = try RunningSessionProcess.runOpenrun(["list"], environment: ["OPENRUN_SOCKET": process.socketPath], in: process.directory)
                #expect(result.status == 0)
                #expect(result.standardError.isEmpty)
                #expect(!Self.holdsControlCharacter(result.standardOutput), "output: \(result.standardOutput.debugDescription)")
                #expect(result.outputLines.count == 1)
                let columns = result.standardOutput.dropLast().split(separator: "\t", omittingEmptySubsequences: false)
                #expect(columns.count == 3)
                #expect(columns.first == Substring(identifier))
                #expect(columns.dropFirst().first?.contains("evil\\u{1B}[31m\\nfake line\\tfake column") == true)
                #expect(columns.last?.hasSuffix("ARG\\u{1B}[31m\\nINJECTED\\tCOLUMN\\\\") == true)
            }
        }

        @Test func anErrorThatHoldsTextFromAClientDrivesNoTerminal() async throws {
            try await RunningSessionProcess.run { process in
                // The program does not exist, so the session process fails and
                // names the program in its failure message.
                let result = try RunningSessionProcess.runOpenrun(
                    ["new", "--", "\u{1B}]52;c;QUJD\u{07}EVILPROGRAM"],
                    environment: ["OPENRUN_SOCKET": process.socketPath],
                    in: process.directory
                )
                #expect(result.status == 1)
                #expect(result.standardError.contains("EVILPROGRAM"), "error: \(result.standardError.debugDescription)")
                #expect(!Self.holdsControlCharacter(result.standardError), "error: \(result.standardError.debugDescription)")
                #expect(result.standardError.contains("\\u{1B}]52;c;QUJD\\u{7}"))
            }
        }

        @Test func anIdentifierTypedWithControlCharactersIsEscapedInTheError() async throws {
            try await RunningSessionProcess.run { process in
                let result = try RunningSessionProcess.runOpenrun(
                    ["read", "zz\u{1B}[2Jzz"],
                    environment: ["OPENRUN_SOCKET": process.socketPath],
                    in: process.directory
                )
                #expect(result.status == 1)
                #expect(!Self.holdsControlCharacter(result.standardError), "error: \(result.standardError.debugDescription)")
                #expect(result.standardError.contains("zz\\u{1B}[2Jzz"))
            }
        }

        @Test func theSocketComesFromTheEnvironmentWhenNoOptionIsGiven() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let result = try RunningSessionProcess.runOpenrun(["list"], environment: ["OPENRUN_SOCKET": process.socketPath], in: process.directory)
                #expect(result.status == 0)
                #expect(result.outputLines.first?.hasPrefix(identifier) == true)
            }
        }

        @Test func theSocketOptionBeatsTheEnvironment() async throws {
            try await RunningSessionProcess.run { process in
                let result = try RunningSessionProcess.runOpenrun(
                    ["list", "--socket", process.socketPath],
                    environment: ["OPENRUN_SOCKET": "/no/such/socket"],
                    in: process.directory
                )
                #expect(result.status == 0)
            }
        }

        @Test func readPrintsScrollbackOnlyOnRequest() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 100; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "100"))
                let screen = try process.screenText(of: identifier)
                let everything = try process.screenText(of: identifier, includeScrollback: true)
                #expect(!screen.hasPrefix("1\n"))
                #expect(everything.hasPrefix("1\n2\n"))
                #expect(everything.hasSuffix(screen))
            }
        }
    }
}
