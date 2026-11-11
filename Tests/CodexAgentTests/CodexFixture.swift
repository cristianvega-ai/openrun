import AgentConversation
import Foundation
@testable import CodexAgent

/// A recorded exchange with the app-server from the folder `Fixtures`.
struct CodexFixture {
    static let folder = URL(fileURLWithPath: "Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL

    let name: String

    var url: URL { Self.folder.appending(path: name + ".jsonl") }

    var steps: [JSONValue] {
        get throws {
            try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { try JSONValue(decoding: Data($0.utf8)) }
        }
    }

    /// The lines that the app-server writes, in order. Each answer takes
    /// the identifier of the request before it, counted from 0.
    var serverBytes: [UInt8] {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var request = -1
            var bytes: [UInt8] = []
            for step in try steps {
                if let method = step["client"]?.string, method != "answer" { request += 1 }
                guard case .object(var line)? = step["server"] else { continue }
                if line["id"] == .string("$request") { line["id"] = .number(Double(request)) }
                bytes += Array(try encoder.encode(JSONValue.object(line))) + [UInt8(ascii: "\n")]
            }
            return bytes
        }
    }

    /// The events of the notifications of the output, in one piece, for
    /// one thread. Answers and requests of the server give none.
    var events: [ConversationEventKind] {
        get throws {
            var reader = CodexMessageReader()
            var mapper = CodexEventMapper()
            return (reader.read(try serverBytes) + reader.finish()).flatMap { incoming -> [ConversationEventKind] in
                switch incoming {
                case .message(.notification(let method, let parameters), _):
                    mapper.events(method: method, parameters: parameters) ?? [.unknown(UnknownLine(reason: .unknownKind, kind: method, text: "", byteCount: 0))]
                case .unreadable(let line, _): [.unknown(line)]
                default: []
                }
            }
        }
    }
}
