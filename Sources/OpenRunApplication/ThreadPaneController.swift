import AgentConversation
import AppKit
import ChatView
import ListContent
import SessionConnection
import SessionProtocol

/// One agent thread as a chat in the third pane (proposal 1 of
/// 2026-11-10). It attaches off the main thread, builds the transcript
/// from the events of the thread, and sends what the user does in the
/// chat to the session process.
@MainActor
final class ThreadPaneController: NSObject {
    let thread: UUID
    let chat: ChatViewController
    var transcript = Transcript()
    private(set) var attachment: ThreadAttachment?
    /// Whether the events that the thread kept came, so the chat shows
    /// each later batch as an update.
    var isReplayComplete = false
    private var isClosed = false
    /// What asks for the next page of the earlier turns: a place in the
    /// history file of Claude Code, or a cursor of Codex. Nil asks for
    /// the newest page.
    var historyCursor: Int?
    var historyToken: String?
    var historyPageCount = 0
    var isLoadingHistory = false
    let socket: SocketLocation
    /// The calls that wait for the socket, in order, off the main thread.
    let work = DispatchQueue(label: "ai.cristianvega.openrun.thread-pane")
    /// Asks the host for the conversation in a terminal, and for the way back.
    var openInTerminal: (() -> Void)?
    var returnFromTerminal: (() -> Void)?
    /// The user chose a new thread under the account with this name. The
    /// empty name is the account of the login shell.
    var continueOnAccount: ((String) -> Void)?
    /// Tells the host why a request or the connection failed.
    var failed: ((String) -> Void)?
    /// Attaches to the thread. Tests give their own.
    var connect: @Sendable (SocketLocation, UUID) throws -> ThreadAttachment = { try SessionClient(location: $0).attachThread($1) }

    init(summary: ThreadSummary, socket: SocketLocation, home: String, otherAccounts: [ChatAccount] = []) {
        (thread, self.socket) = (summary.identifier, socket)
        chat = ChatViewController(facts: Self.facts(of: summary, home: home, otherAccounts: otherAccounts))
        super.init()
        chat.delegate = self
    }

    /// What the chat shows of the thread beside its transcript.
    static func facts(of summary: ThreadSummary, home: String, otherAccounts: [ChatAccount] = []) -> ChatThreadFacts {
        ChatThreadFacts(
            threadIdentifier: summary.identifierText, title: ThreadRowFacts.title(of: summary), agentName: ThreadRowFacts.agentName(summary.agent),
            accountName: summary.accountName, model: model(summary.model), models: (summary.models ?? []).map(model),
            permissionMode: mode(summary.permissionMode), permissionModes: (summary.permissionModes ?? []).map(mode),
            folder: FolderText.shown(summary.folder, home: home), usage: ThreadRowFacts.usageText(of: summary),
            condition: condition(of: summary, otherAccounts: otherAccounts))
    }

    /// The terminal has the conversation, or the account is at its limit
    /// and the thread waits for the reset (proposal 8).
    private static func condition(of summary: ThreadSummary, otherAccounts: [ChatAccount]) -> ChatThreadCondition {
        if summary.terminalSession != nil { return .openInTerminal }
        if let resetTime = ThreadRowFacts.limitResetTime(of: summary) { return .atLimit(resetTime: resetTime, otherAccounts: otherAccounts) }
        return .ready
    }

    private static func model(_ identifier: String) -> ChatChoice {
        ChatChoice(identifier: identifier, title: ThreadRowFacts.modelTitle(identifier))
    }

    private static func mode(_ identifier: String) -> ChatChoice {
        ChatChoice(identifier: identifier, title: ThreadRowFacts.permissionModeTitle(identifier))
    }

    /// The thread has new facts, such as a name.
    func update(_ summary: ThreadSummary, home: String, otherAccounts: [ChatAccount] = []) {
        var facts = Self.facts(of: summary, home: home, otherAccounts: otherAccounts)
        (facts.hasEarlierHistory, facts.isLoadingEarlierHistory) = (chat.facts.hasEarlierHistory, chat.facts.isLoadingEarlierHistory)
        if facts != chat.facts { chat.facts = facts }
    }

    /// The attach ended, on the main thread.
    func attached(_ result: Result<ThreadAttachment, any Error>) {
        switch result {
        case .success(let attachment) where isClosed: attachment.shutdown()
        case .success(let attachment): self.attachment = attachment
        case .failure(let error): failed?("Could not connect to the thread. \(error)")
        }
    }

    /// Detaches. The thread goes on in the session process.
    func close() {
        isClosed = true
        attachment?.shutdown()
        attachment = nil
    }
}
