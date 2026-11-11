import AgentConversation
import Foundation

/// A user message that starts a Codex turn, with changes for this turn
/// and the turns after it.
public struct CodexTurn: Sendable, Hashable {
    /// OpenRun's identifier of the message. The chat shows the message
    /// under it, before and after Codex takes it.
    public var messageIdentifier: String
    public var text: String
    public var images: [MessageImage]
    /// A new model, effort or sandbox, or nil to keep the one before.
    public var model: String?
    public var reasoningEffort: String?
    public var sandbox: CodexSandbox?

    public init(
        messageIdentifier: String, text: String, images: [MessageImage] = [], model: String? = nil,
        reasoningEffort: String? = nil, sandbox: CodexSandbox? = nil
    ) {
        self.messageIdentifier = messageIdentifier
        self.text = text
        self.images = images
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.sandbox = sandbox
    }

    /// The message as the chat shows it before Codex takes it.
    var userMessage: UserMessage {
        UserMessage(identifier: messageIdentifier, text: text, imageCount: images.count, isAccepted: false)
    }

    func parameters(thread: String) -> JSONValue {
        // An image goes as a data URL, so that Codex needs no file of it.
        let images = images.map { image -> JSONValue in
            .object(["type": .string("image"), "url": .string("data:\(image.mediaType);base64,\(image.data.base64EncodedString())")])
        }
        var parameters: [String: JSONValue] = [
            "threadId": .string(thread), "clientUserMessageId": .string(messageIdentifier),
            "input": .array([.object(["type": .string("text"), "text": .string(text)])] + images),
        ]
        if let model { parameters["model"] = .string(model) }
        if let reasoningEffort { parameters["effort"] = .string(reasoningEffort) }
        if let sandbox { parameters["sandboxPolicy"] = sandbox.turnValue }
        return .object(parameters)
    }
}
