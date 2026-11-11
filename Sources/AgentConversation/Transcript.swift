/// The items that a chat shows for one thread, made from its events.
///
/// A pure value: the same events in the same order give the same items and
/// the same identifiers, so the session process, the app and a test agree.
/// Its memory stays within `limits` whatever the agent sends.
public struct Transcript: Sendable, Hashable {
    public let limits: TranscriptLimits
    var storage = TranscriptStorage()
    /// The newest facts of the agent's process.
    public private(set) var agentStart: AgentStart?
    /// The newest usage reading of the account.
    public private(set) var usage: UsageReading?
    /// The events applied so far. An item with no identifier of its own,
    /// such as a notice, takes the number of its event.
    public private(set) var eventCount = 0
    public init(limits: TranscriptLimits = TranscriptLimits()) {
        self.limits = limits
    }

    public init(events: some Sequence<ConversationEvent>, limits: TranscriptLimits = TranscriptLimits()) {
        self.init(limits: limits)
        for event in events { apply(event) }
    }

    public var items: [TranscriptItem] { storage.items }
    /// How many of the oldest items went to keep the transcript in its limits.
    public var removedItemCount: Int { storage.removedItemCount }

    public func item(withIdentifier identifier: String) -> TranscriptItem? {
        storage.item(identifier)
    }

    /// Takes the next event and returns the items that it changed.
    @discardableResult
    public mutating func apply(_ event: ConversationEvent) -> TranscriptChange {
        eventCount += 1
        var change = TranscriptChange()
        switch event.kind {
        case .agentStarted(let start): agentStart = start
        case .usage(let reading): usage = reading
        case .notice(let notice): insertNotice(notice.level, notice.text, &change)
        case .unknown(var line):
            line.text = BoundedText.prefix(of: line.text, byteLimit: limits.detailByteLimit)
            insert("unknown:\(eventCount)", .unknown(line), &change)
        default: break
        }
        change.removed = storage.trim(to: limits)
        return change
    }

    // MARK: - Items

    mutating func insertNotice(_ level: Notice.Level, _ text: String, _ change: inout TranscriptChange) {
        let bounded = BoundedText.prefix(of: text, byteLimit: limits.detailByteLimit)
        insert("notice:\(eventCount)", .notice(Notice(level: level, text: bounded)), &change)
    }

    mutating func insert(_ identifier: String, _ content: TranscriptItemContent, _ change: inout TranscriptChange) {
        storage.insert(TranscriptItem(identifier: identifier, content: content))
        change.inserted.append(identifier)
    }

    /// Changes the item in place, or adds it made by `create` and then
    /// changed. Without `create`, a missing item stays missing.
    mutating func update(
        _ identifier: String, create: TranscriptItemContent? = nil,
        _ change: inout TranscriptChange, _ body: (inout TranscriptItemContent) -> Void
    ) {
        if storage.modify(identifier, body) {
            if !change.inserted.contains(identifier), !change.updated.contains(identifier) {
                change.updated.append(identifier)
            }
        } else if var content = create {
            body(&content)
            insert(identifier, content, &change)
        }
    }
}
