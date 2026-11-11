import Foundation

/// The tool calls and file changes of a transcript.
extension Transcript {
    mutating func applyToolCallEvent(_ kind: ConversationEventKind, _ change: inout TranscriptChange) {
        let limit = limits.detailByteLimit
        switch kind {
        case .toolCallStarted(let start):
            updateToolCall(start.identifier, &change) { if $0.name.isEmpty { $0.name = start.name } }
        case .toolCallInputDelta(let delta):
            updateToolCall(delta.identifier, &change) { call in
                guard call.state == .preparing else { return }
                call.inputText += BoundedText.prefix(of: delta.partialInput, byteLimit: limit - call.inputText.utf8.count)
            }
        case .toolCallInput(let input):
            let bounded = boundedInput(input.input)
            updateToolCall(input.identifier, &change) { call in
                call.name = input.name
                call.input = bounded
                if call.state == .preparing { call.state = .running }
            }
        case .toolCallOutput(let output):
            updateToolCall(output.identifier, &change) { call in
                call.output += BoundedText.prefix(of: output.text, byteLimit: limit - call.output.utf8.count)
                call.outputByteCount += output.text.utf8.count
                if call.state == .preparing { call.state = .running }
            }
        case .toolCallResult(let result):
            updateToolCall(result.identifier, &change) { call in
                // A refusal comes first, and its result is an error too.
                if call.state != .refused { call.state = result.isError ? .failed : .succeeded }
                call.output = BoundedText.prefix(of: result.output, byteLimit: limit)
                call.outputByteCount = result.outputByteCount
                call.exitCode = result.exitCode
            }
            openItems.remove("tool:" + result.identifier)
        case .toolCallRefused(var refusal):
            refusal.message = BoundedText.prefix(of: refusal.message, byteLimit: limit)
            guard let identifier = refusal.identifier else {
                insertNotice(.warning, "\(refusal.toolName) was refused: \(refusal.message)", &change)
                return
            }
            updateToolCall(identifier, &change) { call in
                if call.name.isEmpty { call.name = refusal.toolName }
                call.state = .refused
                call.refusal = refusal
            }
            openItems.remove("tool:" + identifier)
        case .fileChange(var fileChange):
            fileChange.diff = BoundedText.prefix(of: fileChange.diff, byteLimit: limit)
            update("file:" + fileChange.identifier, create: .fileChange(fileChange), &change) { $0 = .fileChange(fileChange) }
        default:
            break
        }
    }

    /// Changes the tool call, or adds it first. An event can come without
    /// the start of its call, as in history or after a lost line.
    private mutating func updateToolCall(_ identifier: String, _ change: inout TranscriptChange, _ body: (inout ToolCallItem) -> Void) {
        update("tool:" + identifier, create: .toolCall(ToolCallItem(name: "")), isOpen: true, &change) { content in
            content.modifyToolCall(body)
        }
    }

    /// The input, or its JSON text cut to the detail limit when the input
    /// is larger, such as a Write call with the content of a large file.
    func boundedInput(_ input: JSONValue) -> JSONValue {
        guard input.estimatedByteCount > limits.detailByteLimit else { return input }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = (try? encoder.encode(input)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return .string(BoundedText.prefix(of: text, byteLimit: limits.detailByteLimit))
    }
}
