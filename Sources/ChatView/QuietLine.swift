import AgentConversation

/// The words of a quiet row that is no tool call: a task of a sub-agent, a
/// notice, a turn that stopped or failed, or a line that this version
/// cannot read. The line opens to its details when it has any.
struct QuietLine: Equatable {
    var symbolName: String
    var title: String
    var status: String?
    /// The words that VoiceOver reads first for the kind of row.
    var kindLabel: String
    /// The parts of the open box. A line without details does not open.
    var details: [String]

    init?(_ content: TranscriptItemContent) {
        switch content {
        case .task(let task):
            let status = task.end.map { $0.status == "completed" ? nil : $0.status.capitalized } ?? "Running"
            let messages = (task.removedMessageCount > 0 ? ["\(task.removedMessageCount) earlier messages are not kept"] : []) + task.messages
            self.init(symbolName: "arrow.triangle.branch", title: task.start?.description ?? "A sub-agent", status: status,
                      kindLabel: "Sub-agent task", details: [task.start?.prompt, messages.isEmpty ? nil : messages.joined(separator: "\n\n"),
                                                            task.end?.summary].compactMap { $0 })
        case .notice(let notice):
            let lines = notice.text.split(separator: "\n", maxSplits: 1)
            self.init(symbolName: notice.level == .information ? "info.circle" : "exclamationmark.triangle",
                      title: lines.first.map(String.init) ?? "", status: nil, kindLabel: "Notice",
                      details: lines.count > 1 ? [notice.text] : [])
        case .turnEnd(let end) where end.outcome == .stopped:
            self.init(symbolName: "stop.circle", title: "Stopped", status: nil, kindLabel: "Turn", details: [])
        case .turnEnd(let end):
            let error = end.errorText ?? "The agent gave no reason."
            self.init(symbolName: "exclamationmark.triangle", title: "The turn failed: " + (error.split(separator: "\n").first ?? ""),
                      status: nil, kindLabel: "Failed turn", details: error.contains("\n") ? [error] : [])
        case .unknown(let line):
            let status = line.kind.map { "Kind \($0)" }
            self.init(symbolName: "questionmark.circle", title: "A line that this version cannot read", status: status,
                      kindLabel: "Unknown line", details: [String(BoundedLines(line.text, lineLimit: 40).text)])
        default: return nil
        }
    }

    init(symbolName: String, title: String, status: String?, kindLabel: String, details: [String]) {
        self.symbolName = symbolName
        self.title = title
        self.status = status
        self.kindLabel = kindLabel
        self.details = details
    }
}
