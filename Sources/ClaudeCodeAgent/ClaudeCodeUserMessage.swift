import AgentConversation
import Foundation

/// The line on Claude Code's standard input that sends a user message.
///
/// OpenRun sends only user messages, and no control request (decision of
/// 2026-11-10): the control requests are the protocol of the Agent SDK.
public enum ClaudeCodeUserMessage {
    /// The image types that the model takes.
    public static let imageMediaTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp"]

    /// One JSON object and a line end. The agent echoes the message back
    /// with the same identifier when it takes it.
    public static func line(identifier: UUID, text: String, images: [MessageImage] = []) throws -> [UInt8] {
        if images.contains(where: { !imageMediaTypes.contains($0.mediaType) }) {
            throw ClaudeCodeUserMessageError.unsupportedImageType
        }
        let content: JSONValue = images.isEmpty ? .string(text) : .array(
            [.object(["type": .string("text"), "text": .string(text)])] + images.map { image in
                .object(["type": .string("image"), "source": .object([
                    "type": .string("base64"), "media_type": .string(image.mediaType),
                    "data": .string(image.data.base64EncodedString()),
                ])])
            })
        let message = JSONValue.object([
            "type": .string("user"), "message": .object(["role": .string("user"), "content": content]),
            "parent_tool_use_id": .null, "session_id": .string(""), "uuid": .string(identifier.uuidString.lowercased()),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // The encoder escapes every line end inside a string, so the
        // message is one line.
        return Array(try encoder.encode(message)) + [UInt8(ascii: "\n")]
    }
}

public enum ClaudeCodeUserMessageError: Error, Equatable {
    /// An image of a type that the model does not take.
    case unsupportedImageType
}
