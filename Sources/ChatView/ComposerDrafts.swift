import AgentConversation

/// The unsent text and images of each thread, while the app runs. At most
/// 50 drafts and 64 MiB stay, and the draft that the user left the longest
/// ago goes first. The host forgets the draft of a thread that closes.
struct ComposerDrafts {
    struct Draft: Equatable {
        var text = ""
        var images: [MessageImage] = []
        /// A message that the user sent while the agent worked. It has not
        /// reached the session process, so only the draft keeps it.
        var heldMessage: ChatOutgoingMessage?
        /// The text holds a message that the user sent and that failed.
        var isSubmitted = false

        var isEmpty: Bool { text.isEmpty && images.isEmpty && heldMessage == nil }
        var byteCount: Int { text.utf8.count + images.reduce(0) { $0 + $1.data.count } + (heldMessage.map { $0.text.utf8.count + $0.images.reduce(0) { $0 + $1.data.count } } ?? 0) }
    }

    /// The drafts of every chat of the app.
    @MainActor static var shared = ComposerDrafts()
    static let countLimit = 50
    static let byteLimit = 64 * 1024 * 1024

    private var drafts: [String: Draft] = [:]
    /// The threads, the one that the user left the longest ago first.
    private var order: [String] = []

    var count: Int { drafts.count }

    func draft(for thread: String) -> Draft {
        drafts[thread] ?? Draft()
    }

    mutating func save(_ draft: Draft, for thread: String) {
        forget(thread)
        guard !draft.isEmpty else { return }
        drafts[thread] = draft
        order.append(thread)
        var bytes = drafts.values.reduce(0) { $0 + $1.byteCount }
        while order.count > 1, order.count > Self.countLimit || bytes > Self.byteLimit {
            // A message of the user is never dropped for room, only a plain draft.
            guard let index = order.firstIndex(where: { drafts[$0]?.heldMessage == nil && drafts[$0]?.isSubmitted != true }) else { break }
            let oldest = order.remove(at: index)
            bytes -= drafts.removeValue(forKey: oldest)?.byteCount ?? 0
        }
    }

    mutating func forget(_ thread: String) {
        drafts[thread] = nil
        order.removeAll { $0 == thread }
    }
}
