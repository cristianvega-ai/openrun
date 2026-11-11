import Foundation

/// One recorded turn, changed so that it answers one user message.
struct FakeAgentTurn {
    let lines: [String]

    /// Reads a fixture file and puts in the identifier of the conversation.
    /// Claude Code echoes the user message before the first line of the
    /// model, so the echo of `userMessage` goes there, marked as a replay,
    /// in place of the recorded one.
    init(file: String, conversationIdentifier: String, userMessage: [String: Any]) throws {
        var lines = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").map(String.init)
        if let recorded = lines.lazy.compactMap({ Self.object($0)?["session_id"] as? String }).first {
            lines = lines.map { $0.replacingOccurrences(of: recorded, with: conversationIdentifier) }
        }
        let modelStart = lines.firstIndex { ["stream_event", "assistant"].contains(Self.type(of: $0)) } ?? lines.count
        var echo = userMessage
        echo["session_id"] = conversationIdentifier
        echo["isReplay"] = true
        let echoLine = String(decoding: try JSONSerialization.data(withJSONObject: echo, options: [.sortedKeys]), as: UTF8.self)
        self.lines = lines[..<modelStart].filter { Self.type(of: $0) != "user" } + [echoLine] + lines[modelStart...]
    }

    /// The position of the line that ends the turn.
    var resultIndex: Int {
        lines.firstIndex { Self.type(of: $0) == "result" } ?? lines.count
    }

    static func object(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    static func type(of line: String) -> String? {
        object(line)?["type"] as? String
    }
}
