/// The text of a conversation for the first message of a new thread, so
/// another agent can go on with the work (proposal 8 of 2026-11-10).
/// OpenRun never moves a conversation to another account, so the new
/// thread gets the words of the earlier one.
public enum TranscriptHandover {
    /// The most characters of the conversation that the message holds.
    /// The newest parts stay, because the work goes on from them.
    public static let characterLimit = 60_000

    static let opening = "Go on with the work of this earlier conversation. Its account reached the usage limit."
    static let cutNotice = "The start of the conversation is left out."

    /// The messages of the user and of the agent, and the files that the
    /// agent changed, in their order. Nil when the transcript holds none.
    public static func message(from transcript: Transcript, characterLimit: Int = TranscriptHandover.characterLimit) -> String? {
        var blocks = transcript.items.compactMap { block(of: $0.content) }
        guard !blocks.isEmpty else { return nil }
        var isCut = false
        while blocks.count > 1, blocks.reduce(0, { $0 + $1.count + 2 }) > characterLimit {
            blocks.removeFirst()
            isCut = true
        }
        // One block alone can be past the limit. Its end stays.
        if let only = blocks.first, blocks.count == 1, only.count > characterLimit {
            (blocks, isCut) = ([String(only.suffix(characterLimit))], true)
        }
        return ([opening] + (isCut ? [cutNotice] : []) + blocks).joined(separator: "\n\n")
    }

    private static func block(of content: TranscriptItemContent) -> String? {
        switch content {
        case .userMessage(let message): message.text.isEmpty ? nil : "User:\n" + message.text
        case .agentMessage(let message): message.text.isEmpty ? nil : "Agent:\n" + message.text
        case .fileChange(let change): "The agent \(change.kind.rawValue) the file \(change.path)."
        default: nil
        }
    }
}
