import Foundation

/// The answer that the `PermissionRequest` hook writes on its standard
/// output before it exits with status 0.
///
/// The settings of the hook set `"onFailure": "block"`, so any other
/// output, a crash or another status denies the call.
public enum ClaudeCodePermissionHookAnswer: Sendable, Hashable {
    case allow
    /// Denies the call. The agent gets the message as the result of the
    /// call, so it can try another way.
    case deny(message: String)

    /// One JSON object and a line end.
    public var output: Data {
        var decision: [String: String]
        switch self {
        case .allow: decision = ["behavior": "allow"]
        case .deny(let message): decision = ["behavior": "deny", "message": message]
        }
        let answer = ["hookSpecificOutput": Answer(hookEventName: "PermissionRequest", decision: decision)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // A dictionary of strings and a struct of strings always encode.
        return (try! encoder.encode(answer)) + Data("\n".utf8)
    }

    private struct Answer: Encodable {
        var hookEventName: String
        var decision: [String: String]
    }
}
