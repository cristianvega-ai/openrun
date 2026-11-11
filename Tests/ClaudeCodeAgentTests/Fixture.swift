import AgentConversation
import ClaudeCodeAgent
import Foundation

/// A recorded output of Claude Code from the folder `Fixtures`.
struct Fixture {
    static let folder = URL(fileURLWithPath: "Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
    static let turns = [
        "plain-turn", "command-turn", "denied-turn", "edit-turn", "sub-agent-turn", "image-turn", "stopped-turn",
        "authentication-failure",
    ]

    let name: String

    var url: URL { Self.folder.appending(path: name + ".jsonl") }

    var bytes: [UInt8] {
        get throws { Array(try Data(contentsOf: url)) }
    }

    /// The events of the whole output, decoded in one piece.
    var events: [ConversationEvent] {
        get throws {
            var decoder = ClaudeCodeOutputDecoder()
            return decoder.decode(try bytes) + decoder.finish()
        }
    }

    var transcript: Transcript {
        get throws { Transcript(events: try events) }
    }
}
