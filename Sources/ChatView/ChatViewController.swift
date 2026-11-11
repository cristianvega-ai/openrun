import AgentConversation
import AppKit

/// The chat of one agent thread, for the third pane of the main window.
///
/// The host gives it a transcript and each change of it, the facts of the
/// thread and an appearance. It reports what the user does through its
/// delegate.
@MainActor public final class ChatViewController: NSViewController {
    public weak var delegate: ChatViewControllerDelegate?
    public var facts: ChatThreadFacts {
        didSet { factsDidChange(from: oldValue) }
    }
    public var appearance: ChatAppearance {
        didSet { if appearance != oldValue { appearanceDidChange() } }
    }
    public private(set) var transcript = Transcript()
    let context: TranscriptRowContext
    let transcriptView: TranscriptView
    let scrollView: TranscriptScrollView
    let composer: ComposerView
    let conditionView = ThreadConditionView()
    let emptyView = EmptyThreadView()
    let jumpButton = JumpToNewestButton()
    let findBar = FindBarView()
    var findMatches: [TranscriptSearch.Match] = []
    var findIndex: Int?
    let agentLabel = NSTextField(labelWithString: "")
    lazy var terminalButton = NSButton(title: "Open in Terminal", target: self, action: #selector(openInTerminal))
    private var builder = TranscriptRowBuilder()

    public init(facts: ChatThreadFacts, appearance: ChatAppearance = .graphite) {
        self.facts = facts
        self.appearance = appearance
        context = TranscriptRowContext(palette: ChatPalette(appearance: appearance))
        transcriptView = TranscriptView(context: context)
        scrollView = TranscriptScrollView(transcriptView: transcriptView)
        composer = ComposerView(palette: context.palette)
        super.init(nibName: nil, bundle: nil)
        connectComposer()
        context.agentName = facts.agentName
        context.actions = self
        context.hasEarlierHistory = facts.hasEarlierHistory
        scrollView.reachedTop = { [weak self] in self?.loadEarlierHistory() }
        transcriptView.viewsPlaced = { [weak self] in self?.connectKeyViews() }
        findBar.isHidden = true
        showThreadState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The smallest size of the pane that still shows a usable chat.
    public var minimumSize: NSSize { NSSize(width: 320, height: 260) }

    /// The title of the pane.
    public var paneTitle: String { facts.title }

    public override func loadView() {
        let root = ChatRootView(palette: context.palette)
        root.addSubview(scrollView)
        for subview in [composer, conditionView, emptyView, jumpButton, findBar] as [NSView] { root.addSubview(subview) }
        view = root
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        layoutChat()
    }

    /// Shows a whole transcript, such as the first one of a thread.
    public func show(_ transcript: Transcript) {
        self.transcript = transcript
        reloadRows(changedItems: nil)
    }

    /// Shows a transcript after one event changed it. Only the rows of the
    /// items that the change names render again.
    public func update(_ transcript: Transcript, change: TranscriptChange) {
        self.transcript = transcript
        reloadRows(changedItems: Set(change.inserted + change.updated))
    }

    private func reloadRows(changedItems: Set<String>?) {
        let showsEarlier = transcript.removedItemCount > 0 || facts.hasEarlierHistory
        let rows = builder.rows(for: transcript, changedItems: changedItems, showsEarlierItems: showsEarlier)
        context.transcript = transcript
        context.documents = builder.documents
        let changedRows = rows.filter { row in
            changedItems.map { changed in row.items.contains(where: changed.contains) } ?? true
        }
        _ = view
        // The row of activity tells whether the agent thinks, which no item
        // names, so it shows again on each change.
        transcriptView.setRows(rows, changed: Set(changedRows.map(\.key) + ["activity"]))
        for row in changedRows {
            if case .permissionRequest(let item)? = row.items.first.flatMap(context.item) {
                PermissionRequestRowView.announce(item, context: context)
            }
        }
        composer.setBusy(transcript.state == .inProgress || transcript.state == .needsUser)
        showThreadState()
    }

    private func factsDidChange(from old: ChatThreadFacts) {
        context.agentName = facts.agentName
        if facts.threadIdentifier != old.threadIdentifier { switchDraft(from: old.threadIdentifier) }
        composer.show(facts, palette: context.palette)
        showThreadState()
        context.hasEarlierHistory = facts.hasEarlierHistory
        context.isLoadingEarlierHistory = facts.isLoadingEarlierHistory
        if (facts.agentName, facts.hasEarlierHistory, facts.isLoadingEarlierHistory)
            != (old.agentName, old.hasEarlierHistory, old.isLoadingEarlierHistory) {
            reloadRows(changedItems: nil)
        }
    }

    private func appearanceDidChange() {
        context.palette = ChatPalette(appearance: appearance)
        (view as? ChatRootView)?.palette = context.palette
        composer.show(facts, palette: context.palette)
        showThreadState()
        reloadRows(changedItems: nil)
    }
}

extension ChatViewController: TranscriptRowActions {
    func openLink(_ target: String) {
        delegate?.chatViewController(self, openLink: target)
    }

    func toggle(_ part: String, in row: TranscriptRowView) {
        if context.openedParts.remove(part) == nil { context.openedParts.insert(part) }
        scrollView.keepInPlace(row.row.key)
    }

    /// Asks the host once for the earlier history, until it loads.
    func loadEarlierHistory() {
        guard facts.hasEarlierHistory, !facts.isLoadingEarlierHistory else { return }
        facts.isLoadingEarlierHistory = true
        delegate?.chatViewControllerLoadEarlierHistory(self)
    }

    func answerPermissionRequest(_ identifier: String, with answer: ChatPermissionAnswer) {
        delegate?.chatViewController(self, answerPermissionRequest: identifier, with: answer)
    }
}
