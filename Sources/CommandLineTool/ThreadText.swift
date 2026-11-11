import AgentConversation
import Foundation
import UntrustedText

/// The conversation of a thread as plain text, for `openrun thread read`.
///
/// The agent, its tools and the user chose the text. An escape sequence in
/// it would drive the terminal of whoever reads the thread, so each
/// control character is escaped, and only the line breaks of a message
/// stay. A backslash stays as it is, because the text is often code.
enum ThreadText {
    /// One block for each item of the transcript, with an empty line between two blocks.
    static func text(of events: [ConversationEvent]) -> String {
        Transcript(events: events).items.compactMap { block(of: $0.content) }.map { $0 + "\n" }.joined(separator: "\n")
    }

    static func block(of content: TranscriptItemContent) -> String? {
        switch content {
        case .userMessage(let message):
            "You" + (message.imageCount > 0 ? " (with \(message.imageCount) images)" : "") + ":\n" + lines(message.text)
        case .agentMessage(let message):
            "Agent:\n" + lines(message.text)
        case .toolCall(let call):
            "Tool \(oneLine(call.name)) (\(call.state.rawValue)): " + oneLine(input(of: call))
        case .fileChange(let change):
            "File \(change.kind.rawValue): " + oneLine(change.path)
        case .permissionRequest(let item):
            "Permission for \(oneLine(item.request.toolName)): " + (item.end?.outcome.rawValue ?? "waits for your answer in OpenRun")
        case .task(let task):
            "Task: " + oneLine(task.start?.description ?? "") + (task.end.map { " (\(oneLine($0.status)))" } ?? "")
        case .turnEnd(let end):
            switch end.outcome {
            case .done: nil
            case .stopped: "The turn stopped."
            case .failed: "The turn failed: " + oneLine(end.errorText ?? "")
            }
        case .notice(let notice):
            "Notice: " + oneLine(notice.text)
        case .unknown(let line):
            "Unknown line: " + oneLine(line.text)
        }
    }

    /// The complete input of a tool call as JSON, or what came of it so far.
    private static func input(of call: ToolCallItem) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let input = call.input, let data = try? encoder.encode(input) else { return call.inputText }
        return String(decoding: data, as: UTF8.self)
    }

    /// Text of many lines: each line is escaped, and the line breaks stay.
    private static func lines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { PrintableText.escapingControlCharacters(in: String($0)) }.joined(separator: "\n")
    }

    /// Text for one line, at most 500 characters. A line break in it shows as `\n`.
    private static func oneLine(_ text: String) -> String {
        PrintableText.escapingControlCharacters(in: text.count > 500 ? String(text.prefix(500)) + "…" : text)
    }
}
