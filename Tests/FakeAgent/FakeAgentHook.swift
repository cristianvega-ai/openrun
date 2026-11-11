import Foundation

/// Runs the permission hook as Claude Code does: the request goes to the
/// standard input of the hook, and the answer comes from its standard
/// output. With `"onFailure": "block"`, any failure of the hook denies.
enum FakeAgentHook {
    /// `allow`, `deny: MESSAGE`, or `blocked` when the hook failed.
    static func decision(of hook: [String], conversationIdentifier: String, environment: [String: String]) -> String {
        guard let command = hook.first, let file = environment["FAKE_AGENT_PERMISSION_REQUEST"],
              var request = try? String(contentsOfFile: file, encoding: .utf8) else { return "blocked" }
        if let recorded = (try? JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any])?["session_id"] as? String {
            request = request.replacingOccurrences(of: recorded, with: conversationIdentifier)
        }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = Array(hook.dropFirst())
        (process.standardInput, process.standardOutput, process.standardError) = (input, output, FileHandle.nullDevice)
        guard (try? process.run()) != nil else { return "blocked" }
        try? input.fileHandleForWriting.write(contentsOf: Data(request.utf8))
        try? input.fileHandleForWriting.close()
        let answer = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let specific = (try? JSONSerialization.jsonObject(with: answer) as? [String: Any])?["hookSpecificOutput"] as? [String: Any]
        guard process.terminationStatus == 0, let decision = specific?["decision"] as? [String: String] else { return "blocked" }
        switch decision["behavior"] {
        case "allow": return "allow"
        case "deny": return "deny: " + (decision["message"] ?? "")
        default: return "blocked"
        }
    }
}
