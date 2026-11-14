import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing

/// A program that the agent of a thread started acts for the agent, so the
/// rule that asks the user first applies to it (decision of 2026-11-10).
@Suite struct ThreadAgentPlaceTests {
    @Test func anAgentOfAThreadMayNotReadAnotherTerminal() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The agent reads the screen of another session, and then waits.
        let agent = folder.appendingPathComponent("agent")
        let script = """
            #!/bin/sh
            d="$OPENRUN_TEST_FOLDER"
            "$OPENRUN_TEST_TOOL" --socket "$(cat "$d/socket")" read "$(cat "$d/target")" > "$d/output" 2>&1
            echo "status $?" >> "$d/output"
            exec sleep 60
            """
        try script.write(to: agent, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        let process = try RunningSessionProcess(
            arguments: ["--agent-program", agent.path, "--own-environment-for-agents"],
            environment: ["PATH": "/usr/bin:/bin", "OPENRUN_TEST_FOLDER": folder.path, "OPENRUN_TEST_TOOL": RunningSessionProcess.commandExecutable.path])
        defer { process.stop() }
        let target = try process.createSession(program: ["/bin/sh", "-c", "echo secret-marker; exec sleep 60"])
        try process.socketPath.write(to: folder.appendingPathComponent("socket"), atomically: true, encoding: .utf8)
        try target.write(to: folder.appendingPathComponent("target"), atomically: true, encoding: .utf8)
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        let thread = try client.createThread(agent: "claude-code", folder: folder.path).identifier
        _ = try client.sendThreadMessage(thread, text: "Read the other terminal.", images: [])
        let output = folder.appendingPathComponent("output")
        #expect(await eventually { (try? String(contentsOf: output, encoding: .utf8))?.contains("status") == true })
        // An agent is no session, so the read is refused with no question.
        let text = try String(contentsOf: output, encoding: .utf8)
        #expect(!text.contains("secret-marker") && text.hasSuffix("status 1\n") && text.contains("An agent may not act on another terminal"))
    }
}
