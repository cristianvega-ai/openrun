/// What a row asks of the view that holds it.
@MainActor protocol TranscriptRowActions: AnyObject {
    /// The user clicked a link. Nothing opens it without the host.
    func openLink(_ target: String)
    /// The user opened or closed a part of a row, such as the output of a
    /// tool call. The row's height changes.
    func toggle(_ part: String, in row: TranscriptRowView)
    /// The user asked for the messages before the first one.
    func loadEarlierHistory()
    /// The user answered a permission request.
    func answerPermissionRequest(_ identifier: String, with answer: ChatPermissionAnswer)
}
