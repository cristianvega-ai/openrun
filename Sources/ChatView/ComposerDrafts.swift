/// The unsent text of each thread, so a draft waits while the user looks
/// at another thread. The drafts stay only while the app runs.
@MainActor enum ComposerDrafts {
    private static var drafts: [String: String] = [:]

    static func draft(for thread: String) -> String {
        drafts[thread] ?? ""
    }

    static func save(_ text: String, for thread: String) {
        drafts[thread] = text.isEmpty ? nil : text
    }
}
