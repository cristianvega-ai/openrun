import Foundation
import PseudoTerminal
import Testing
@testable import AgentProgram

@Suite struct LoginShellEnvironmentTests {
    /// A shell in a script: it runs `body`, and then the command after `-c`.
    func shell(_ body: String) throws -> (LoginShell, URL) {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "login-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appending(path: "shell")
        try "#!/bin/sh\n\(body)\nshift 3\nexec /bin/sh -c \"$1\"\n".write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
        return (LoginShell(path: script.path), folder)
    }

    func read(_ body: String, timeLimit: Duration = .seconds(10), byteLimit: Int = 1024 * 1024) async throws -> [String: String]? {
        let (shell, folder) = try shell(body)
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = ["PATH": "/usr/bin:/bin", "GREETING": "line one\nline two", "HOME": folder.path]
        return await LoginShellEnvironment.read(shell: shell, base: base, folder: folder.path, timeLimit: timeLimit, byteLimit: byteLimit)
    }

    @Test func theEnvironmentOfTheShellComesBetweenTheMarkersWithoutNoise() async throws {
        let environment = try #require(try await read("echo 'Welcome!'; export TOOL_PATH=/opt/tool; printf '\\033[0m'"))
        #expect(environment["TOOL_PATH"] == "/opt/tool")
        #expect(environment["GREETING"] == "line one\nline two")
        #expect(environment["PWD"] == nil)
        #expect(environment["SHLVL"] == nil)
        #expect(environment["_"] == nil)
    }

    @Test func aShellThatFailsWaitsOrFloodsGivesNothing() async throws {
        #expect(try await read("exit 1") == nil)
        let start = ContinuousClock.now
        #expect(try await read("sleep 300", timeLimit: .milliseconds(300)) == nil)
        #expect(ContinuousClock.now - start < .seconds(10))
        #expect(try await read("head -c 3000000 /dev/zero", byteLimit: 100_000) == nil)
        #expect(await LoginShellEnvironment.read(shell: LoginShell(path: "/no/such/shell"), base: [:], folder: "/") == nil)
    }

    @Test func theRealShellOfTheUserGivesAPath() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "login-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // An empty home folder, so that no profile of the user runs.
        let base = ["HOME": folder.path, "PATH": "/usr/bin:/bin", "ZDOTDIR": folder.path]
        let environment = await LoginShellEnvironment.read(shell: LoginShell(path: "/bin/zsh"), base: base, folder: folder.path)
        #expect(environment?["PATH"]?.contains("/usr/bin") == true)
    }

    @Test func parseKeepsOnlyNamedEntriesBetweenTheMarkers() {
        #expect(LoginShellEnvironment.parse("noise MA=1\u{0}=x\u{0}junk\u{0}B=a=b\u{0}M tail", marker: "M") == ["A": "1", "B": "a=b"])
        #expect(LoginShellEnvironment.parse("M only one", marker: "M") == nil)
        #expect(LoginShellEnvironment.parse("nothing", marker: "M") == nil)
    }
}
