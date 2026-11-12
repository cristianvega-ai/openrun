/// The items that a chat shows for one thread, made from its events.
///
/// A pure value: the same events in the same order give the same items and
/// the same identifiers, so the session process, the app and a test agree.
/// Its memory stays within `limits` whatever the agent sends.
public struct Transcript: Sendable, Hashable {
    public let limits: TranscriptLimits
    var storage = TranscriptStorage()
    public private(set) var state: ThreadState = .idle

    /// Whether the newest turn failed because the agent has no valid
    /// login. A chat then tells the user to sign in.
    public var needsSignIn: Bool {
        guard state == .failed else { return false }
        for item in items.reversed() {
            if case .turnEnd(let end) = item.content { return end.errorKind == TurnEnd.notSignedIn }
        }
        return false
    }
    /// The thinking that goes on now, or nil.
    public private(set) var thinking: Thinking?
    /// The newest facts of the agent's process.
    public private(set) var agentStart: AgentStart?
    /// The newest usage reading of the account.
    public private(set) var usage: UsageReading?
    /// The events applied so far. An item with no identifier of its own,
    /// such as a notice, takes the number of its event.
    public private(set) var eventCount = 0
    /// Items that the end of a turn closes: text that streams, tool calls
    /// that run, and permission requests that wait.
    var openItems: Set<String> = []
    var waitingPermissions: Set<String> = []
    /// The task item of each tool call that started a sub-agent.
    var taskItems: [String: String] = [:]
    /// The tool calls of each task item, so that its entries in
    /// `taskItems` go when the item goes.
    var taskCalls: [String: [String]] = [:]
    /// The newest items that the trim dropped, at least 1,024 of them. A
    /// late event of such an item, such as a delta or a result, changes
    /// nothing.
    var droppedItems: RecentIdentifiers

    public init(limits: TranscriptLimits = TranscriptLimits()) {
        self.limits = limits
        droppedItems = RecentIdentifiers(capacity: max(limits.itemLimit, 1_024))
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
        case .userMessage(let message): applyUserMessage(message, &change)
        case .agentTextDelta(let delta): applyText(delta.text, of: delta.itemIdentifier, isComplete: false, &change)
        case .agentText(let text): applyText(text.text, of: text.itemIdentifier, isComplete: true, &change)
        case .thinking(let new):
            thinking = new.isComplete ? nil : Thinking(
                itemIdentifier: new.itemIdentifier ?? thinking?.itemIdentifier,
                estimatedTokens: new.estimatedTokens ?? thinking?.estimatedTokens, isComplete: false)
        case .turnEnded(var end):
            end.errorText = end.errorText.map { BoundedText.prefix(of: $0, byteLimit: limits.detailByteLimit) }
            insert("turn:\(eventCount)", .turnEnd(end), &change)
            closeOpenItems(&change)
        case .processEnded(let end): applyProcessEnd(end, &change)
        case .toolCallStarted, .toolCallInputDelta, .toolCallInput, .toolCallOutput, .toolCallResult, .toolCallRefused, .fileChange:
            applyToolCallEvent(event.kind, &change)
        case .permissionRequested, .permissionEnded, .taskStarted, .taskMessage, .taskEnded:
            applyRequestEvent(event.kind, &change)
        case .usage(let reading): usage = reading
        case .notice(let notice): insertNotice(notice.level, notice.text, &change)
        case .unknown(var line):
            line.text = BoundedText.prefix(of: line.text, byteLimit: limits.detailByteLimit)
            insert("unknown:\(eventCount)", .unknown(line), &change)
        case .turnStarted, .agentStatus:
            break
        }
        updateState(after: event.kind)
        change.removed = storage.trim(to: limits)
        forget(change.removed)
        return change
    }

    /// Drops what the transcript kept about items that it trimmed, so that
    /// its memory stays bounded however many items come and go, and
    /// remembers the newest of them.
    mutating func forget(_ removed: [String]) {
        for identifier in removed {
            droppedItems.insert(identifier)
            openItems.remove(identifier)
            waitingPermissions.remove(identifier)
            for call in taskCalls.removeValue(forKey: identifier) ?? [] where taskItems[call] == identifier {
                taskItems[call] = nil
                // A later message of the task looks for this name.
                droppedItems.insert("task:" + call)
            }
        }
        if waitingPermissions.isEmpty, state == .needsUser { state = .inProgress }
    }

    // MARK: - Messages

    private mutating func applyUserMessage(_ message: UserMessage, _ change: inout TranscriptChange) {
        var new = message
        new.text = BoundedText.prefix(of: message.text, byteLimit: limits.messageByteLimit)
        new.isAccepted = false
        update("user:" + message.identifier, create: .userMessage(new), &change) { content in
            content.modifyUserMessage { $0.isAccepted = $0.isAccepted || message.isAccepted }
        }
    }

    private mutating func applyText(_ text: String, of itemIdentifier: String, isComplete: Bool, _ change: inout TranscriptChange) {
        let identifier = "text:" + itemIdentifier
        let limit = limits.messageByteLimit
        update(identifier, create: .agentMessage(AgentMessage(text: "", isComplete: false)), isOpen: true, &change) { content in
            content.modifyAgentMessage { message in
                if isComplete {
                    message.text = BoundedText.prefix(of: text, byteLimit: limit)
                    message.isComplete = true
                } else if !message.isComplete {
                    message.text += BoundedText.prefix(of: text, byteLimit: limit - message.text.utf8.count)
                }
            }
        }
        if isComplete {
            openItems.remove(identifier)
            thinking = nil
        }
    }

    // MARK: - Ends

    private mutating func applyProcessEnd(_ end: ProcessEnd, _ change: inout TranscriptChange) {
        if end.isFailure {
            let how = end.signal.map { "by signal \($0)" } ?? "with status \(end.exitStatus ?? -1)"
            let detail = end.standardErrorText.map { "\n" + $0 } ?? ""
            insertNotice(.error, "The agent's process ended \(how)." + detail, &change)
        }
        closeOpenItems(&change)
    }

    /// A turn or a process that ends also ends what it left open.
    private mutating func closeOpenItems(_ change: inout TranscriptChange) {
        // A set has no fixed order, and the change must be the same for the
        // same events, so the items close in the order of their names.
        for identifier in openItems.sorted() {
            update(identifier, &change) { content in
                content.modifyAgentMessage { $0.isComplete = true }
                content.modifyToolCall { call in
                    if call.state == .preparing || call.state == .running { call.state = .interrupted }
                }
                content.modifyPermissionRequest { item in
                    if item.isWaiting { item.end = PermissionEnd(identifier: item.request.identifier, outcome: .cancelled) }
                }
            }
        }
        openItems.removeAll()
        waitingPermissions.removeAll()
        thinking = nil
    }

    private mutating func updateState(after kind: ConversationEventKind) {
        switch kind {
        case .turnEnded(let end):
            state = switch end.outcome {
            case .done: .finishedTurn
            case .stopped: .idle
            case .failed: .failed
            }
        case .processEnded(let end):
            if end.isFailure {
                state = .failed
            } else if state == .inProgress || state == .needsUser {
                state = .idle
            }
        case .permissionEnded:
            if state == .needsUser { state = .inProgress }
        case .agentStarted, .usage, .notice, .agentStatus, .unknown:
            break
        default:
            state = .inProgress
        }
        if !waitingPermissions.isEmpty { state = .needsUser }
    }

    // MARK: - Items

    mutating func insertNotice(_ level: Notice.Level, _ text: String, _ change: inout TranscriptChange) {
        let bounded = BoundedText.prefix(of: text, byteLimit: limits.detailByteLimit)
        insert("notice:\(eventCount)", .notice(Notice(level: level, text: bounded)), &change)
    }

    mutating func insert(_ identifier: String, _ content: TranscriptItemContent, isOpen: Bool = false, _ change: inout TranscriptChange) {
        storage.insert(TranscriptItem(identifier: identifier, content: content))
        change.inserted.append(identifier)
        if isOpen { openItems.insert(identifier) }
    }

    /// Changes the item in place, or adds it made by `create` and then
    /// changed. Without `create`, or when the trim dropped the item, a
    /// missing item stays missing.
    mutating func update(
        _ identifier: String, create: TranscriptItemContent? = nil, isOpen: Bool = false,
        _ change: inout TranscriptChange, _ body: (inout TranscriptItemContent) -> Void
    ) {
        if storage.modify(identifier, body) {
            if !change.inserted.contains(identifier), !change.updated.contains(identifier) {
                change.updated.append(identifier)
            }
        } else if var content = create, !droppedItems.contains(identifier) {
            body(&content)
            insert(identifier, content, isOpen: isOpen, &change)
        }
    }
}
