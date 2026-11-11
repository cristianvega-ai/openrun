import Darwin
import Foundation
import Testing
@testable import AgentProgram

@Suite struct AgentProgramLaunchTests {
    func launch(_ executable: String = "cat", arguments: [String] = [], folder: String = "/", environment: [String: String] = [:]) -> AgentProgramLaunch {
        AgentProgramLaunch(executablePath: executable, arguments: arguments, folder: folder, environment: environment)
    }

    @Test func aValueThatWouldReachTheProgramChangedIsRefused() {
        let refusals: [(AgentProgramLaunch, String)] = [
            (launch(""), "the program name is empty"),
            (launch("c\u{0}at"), "the program name holds a NUL character"),
            (launch(arguments: ["a", "b\u{0}"]), "argument 2 holds a NUL character"),
            (launch(folder: "/tmp\u{0}"), "the folder holds a NUL character"),
            (launch(environment: ["": "x"]), "an environment variable has an empty name"),
            (launch(environment: ["A=B": "x"]), "an environment variable name holds an equals sign (=)"),
            (launch(environment: ["A\u{0}": "x"]), "an environment variable name holds a NUL character"),
            (launch(environment: ["A": "x\u{0}"]), "the value of an environment variable holds a NUL character"),
        ]
        for (launch, problem) in refusals {
            #expect(throws: AgentProgramError.invalidLaunchValue(problem: problem)) { try launch.checkValues() }
        }
        #expect(throws: Never.self) { try launch(environment: ["A": "=x"]).checkValues() }
    }

    @Test func theFolderMustBeAFolderThatOpens() throws {
        #expect(throws: AgentProgramError.systemCallFailed(function: "chdir", code: ENOENT)) { try launch(folder: "/no/such/folder").checkFolder() }
        #expect(throws: AgentProgramError.systemCallFailed(function: "chdir", code: ENOTDIR)) { try launch(folder: "/bin/sh").checkFolder() }
        try launch(folder: NSTemporaryDirectory()).checkFolder()
    }

    @Test func aBareNameIsFoundInThePathOfTheLaunchAndARelativeEntryInTheFolder() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "tools/folder-tool"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appending(path: "tools/tool").path, contents: Data("#!/bin/sh\n".utf8))
        chmod(folder.appending(path: "tools/tool").path, 0o755)
        let environment = ["PATH": "tools:/usr/bin"]
        #expect(try launch("tool", folder: folder.path, environment: environment).resolvedExecutablePath() == "tools/tool")
        #expect(try launch("env", folder: folder.path, environment: environment).resolvedExecutablePath() == "/usr/bin/env")
        #expect(try launch("./x/y", environment: environment).resolvedExecutablePath() == "./x/y")
        // A folder with the name of the program is not the program.
        #expect(throws: AgentProgramError.programNotFound(name: "folder-tool")) {
            try launch("folder-tool", folder: folder.path, environment: environment).resolvedExecutablePath()
        }
        #expect(try launch("ls").resolvedExecutablePath() == "/bin/ls")
    }
}
