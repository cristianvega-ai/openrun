/// What `openrun thread` does, after the arguments are checked.
enum ThreadAction: Equatable {
    case list(printsJSON: Bool)
    /// A nil agent is Claude Code, and a nil folder is the current one.
    /// `text` is the first message.
    case new(agent: String?, folder: String?, model: String?, mode: String?, name: String?, account: String? = nil, text: String?)
    case send(thread: String, text: String)
    case read(thread: String, printsJSON: Bool)
    case stop(thread: String)
    /// A nil name removes the name.
    case rename(thread: String, name: String?)
    case close(thread: String)
}
