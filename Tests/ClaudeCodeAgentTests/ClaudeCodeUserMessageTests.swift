import AgentConversation
import Foundation
import Testing
import ClaudeCodeAgent

@Suite struct ClaudeCodeUserMessageTests {
    let identifier = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    @Test func aTextMessageIsOneLineWithTheTextAsItsContent() throws {
        let line = try ClaudeCodeUserMessage.line(identifier: identifier, text: "Line one\nline \"two\"")
        #expect(String(decoding: line, as: UTF8.self) == #"{"message":{"content":"Line one\nline \"two\"","role":"user"},"parent_tool_use_id":null,"session_id":"","type":"user","uuid":"00000000-0000-4000-8000-000000000001"}"# + "\n")
        #expect(line.filter { $0 == UInt8(ascii: "\n") }.count == 1)
    }

    @Test func imagesFollowTheTextAsBase64Blocks() throws {
        let image = MessageImage(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let line = try ClaudeCodeUserMessage.line(identifier: identifier, text: "What color?", images: [image])
        let value = try JSONValue(decoding: Data(line))
        #expect(value["message"]?["content"] == .array([
            .object(["type": .string("text"), "text": .string("What color?")]),
            .object(["type": .string("image"), "source": .object([
                "type": .string("base64"), "media_type": .string("image/png"), "data": .string("iVBORw=="),
            ])]),
        ]))
    }

    @Test func anImageOfAnotherTypeIsRefused() {
        #expect(throws: ClaudeCodeUserMessageError.unsupportedImageType) {
            try ClaudeCodeUserMessage.line(identifier: identifier, text: "", images: [MessageImage(mediaType: "image/tiff", data: Data())])
        }
    }
}
