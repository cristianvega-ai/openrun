/// The items of a transcript in order, found by identifier, with the books
/// of their size.
///
/// An identifier maps to an absolute position, which never changes, so the
/// removal of the oldest items does not touch the map of the others.
struct TranscriptStorage: Sendable, Hashable {
    private(set) var items: [TranscriptItem] = []
    private var byteCounts: [Int] = []
    private var positions: [String: Int] = [:]
    private var firstPosition = 0
    private(set) var byteCount = 0
    private(set) var removedItemCount = 0

    func item(_ identifier: String) -> TranscriptItem? {
        positions[identifier].map { items[$0 - firstPosition] }
    }

    func contains(_ identifier: String) -> Bool {
        positions[identifier] != nil
    }

    /// Adds an item at the end. The identifier must be new.
    mutating func insert(_ item: TranscriptItem) {
        positions[item.identifier] = firstPosition + items.count
        let size = item.content.estimatedByteCount
        items.append(item)
        byteCounts.append(size)
        byteCount += size
    }

    /// Changes the content of an item in place. Returns false when no item
    /// has the identifier.
    @discardableResult
    mutating func modify(_ identifier: String, _ body: (inout TranscriptItemContent) -> Void) -> Bool {
        guard let position = positions[identifier] else { return false }
        let index = position - firstPosition
        body(&items[index].content)
        let size = items[index].content.estimatedByteCount
        byteCount += size - byteCounts[index]
        byteCounts[index] = size
        return true
    }

    /// Removes the oldest items until the rest fit the limits, and returns
    /// their identifiers. The newest item always stays.
    mutating func trim(to limits: TranscriptLimits) -> [String] {
        var count = 0
        var bytes = byteCount
        while items.count - count > 1, items.count - count > limits.itemLimit || bytes > limits.byteLimit {
            bytes -= byteCounts[count]
            count += 1
        }
        guard count > 0 else { return [] }
        let removed = items[..<count].map(\.identifier)
        removed.forEach { positions[$0] = nil }
        items.removeFirst(count)
        byteCounts.removeFirst(count)
        byteCount = bytes
        firstPosition += count
        removedItemCount += count
        return removed
    }
}

extension TranscriptItemContent {
    /// The bytes of text that the item holds, with a small cost for the
    /// item itself, so that many empty items also reach the limit.
    var estimatedByteCount: Int {
        let text: Int = switch self {
        case .userMessage(let message): message.text.utf8.count
        case .agentMessage(let message): message.text.utf8.count
        case .toolCall(let call):
            call.name.utf8.count + call.inputText.utf8.count + call.output.utf8.count
                + (call.input?.estimatedByteCount ?? 0) + (call.refusal?.message.utf8.count ?? 0)
        case .fileChange(let change): change.path.utf8.count + change.diff.utf8.count
        case .permissionRequest(let item): item.request.toolName.utf8.count + item.request.input.estimatedByteCount
        case .task(let task):
            (task.start.map { $0.description.utf8.count + $0.prompt.utf8.count } ?? 0)
                + task.messages.reduce(0) { $0 + $1.utf8.count } + (task.end?.summary?.utf8.count ?? 0)
        case .turnEnd(let end): end.errorText?.utf8.count ?? 0
        case .notice(let notice): notice.text.utf8.count
        case .unknown(let line): line.text.utf8.count
        }
        return 64 + text
    }
}

extension JSONValue {
    /// About the bytes of the value's JSON text.
    var estimatedByteCount: Int {
        switch self {
        case .null, .bool, .number: 8
        case .string(let value): value.utf8.count + 2
        case .array(let values): values.reduce(2) { $0 + $1.estimatedByteCount + 1 }
        case .object(let members): members.reduce(2) { $0 + $1.key.utf8.count + $1.value.estimatedByteCount + 4 }
        }
    }
}
