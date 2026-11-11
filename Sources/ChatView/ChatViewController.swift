import AgentConversation
import AppKit

/// The chat of one agent thread, for the third pane of the main window.
///
/// The host gives it a transcript and each change of it, the facts of the
/// thread and an appearance. It reports what the user does through its
/// delegate.
@MainActor public final class ChatViewController: NSViewController {
    public var facts: ChatThreadFacts {
        didSet { factsDidChange(from: oldValue) }
    }
    public let appearance: ChatAppearance
    public private(set) var transcript = Transcript()
    let context: TranscriptRowContext
    let transcriptView: TranscriptView
    let scrollView: TranscriptScrollView
    private var builder = TranscriptRowBuilder()

    public init(facts: ChatThreadFacts, appearance: ChatAppearance = .graphite) {
        self.facts = facts
        self.appearance = appearance
        context = TranscriptRowContext(palette: ChatPalette(appearance: appearance))
        transcriptView = TranscriptView(context: context)
        scrollView = TranscriptScrollView(transcriptView: transcriptView)
        super.init(nibName: nil, bundle: nil)
        context.agentName = facts.agentName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The smallest size of the pane that still shows a usable chat.
    public var minimumSize: NSSize { NSSize(width: 320, height: 260) }

    public override func loadView() {
        let root = ChatRootView(palette: context.palette)
        root.addSubview(scrollView)
        view = root
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        scrollView.frame = view.bounds
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
        transcriptView.setRows(rows, changed: Set(changedRows.map(\.key)))
    }

    private func factsDidChange(from old: ChatThreadFacts) {
        context.agentName = facts.agentName
    }
}
