import SessionProtocol
import TerminalEmulation

/// The resizes of a session while a line editor answers a new size.
///
/// The program gets the new size at once. The session's copy of the screen,
/// and each client that follows it, take the size where the editor has erased
/// its lines (see `LineEditorAnswer`). A resize that comes before that waits,
/// and a newer one replaces it. So the editor answers one size at a time, and
/// its answer always counts rows at the width of the copy.
struct LineEditorWait {
    /// A resize from a client, with what the session owes that client.
    struct Request {
        var size: SessionSize
        /// Nil after the client left.
        var requester: ObjectIdentifier?
        var confirms: Bool
        /// The requester's real terminal reports the size to the program.
        var reportsItself: Bool
    }

    /// The size that the program has and the copy of the screen does not.
    private(set) var request: Request?
    /// Tells a late time limit from the limit of the current wait.
    private(set) var number = 0
    private var answer: LineEditorAnswer?
    /// The output bytes that the program wrote before it got the size. An
    /// erase in them is older than the size, so it is not the answer.
    private var earlierByteCount = 0
    /// The newest resize that came during the wait.
    private var next: Request?
    /// The clients whose confirmed resize a newer one replaced. They hear of
    /// the size that applies when the waits end.
    private var clientsOwedTheSize: Set<ObjectIdentifier> = []

    var isWaiting: Bool { request != nil }

    /// Starts to wait for the editor's answer to the request's size, and
    /// returns the number of the wait. The answer comes after the
    /// `earlierByteCount` bytes of output that the session has not parsed yet.
    mutating func start(_ request: Request, editor: LineEditor, earlierByteCount: Int) -> Int {
        number += 1
        self.request = request
        answer = LineEditorAnswer(editor: editor)
        self.earlierByteCount = max(0, earlierByteCount)
        return number
    }

    /// Where in the output the editor's answer ends, or nil.
    mutating func end(in bytes: ArraySlice<UInt8>) -> LineEditorAnswer.End? {
        guard answer != nil else { return nil }
        let earlier = min(earlierByteCount, bytes.count)
        earlierByteCount -= earlier
        return answer?.end(in: bytes.dropFirst(earlier))
    }

    /// Notes a resize that changes nothing: a size of zero rows or columns.
    /// Only its confirmation is due, with the size that applies at the end.
    mutating func owe(_ client: ObjectIdentifier) {
        clientsOwedTheSize.insert(client)
    }

    /// Keeps a resize for the end of the wait. It replaces an older one.
    mutating func queue(_ request: Request) {
        if let replaced = next, replaced.confirms, let client = replaced.requester {
            clientsOwedTheSize.insert(client)
        }
        // Only a newer confirmed resize of the client answers for the older one.
        if request.confirms, let client = request.requester { clientsOwedTheSize.remove(client) }
        next = request
    }

    /// Ends the wait, and returns its request and the resize that came during it.
    mutating func finish() -> (finished: Request, next: Request?)? {
        guard let request else { return nil }
        defer { (self.request, answer, next) = (nil, nil, nil) }
        return (request, next)
    }

    /// The clients that the session still owes a size. Call it when no wait is left.
    mutating func takeClientsOwedTheSize() -> Set<ObjectIdentifier> {
        defer { clientsOwedTheSize = [] }
        return clientsOwedTheSize
    }

    /// Forgets a client that left. Its resizes still apply.
    mutating func forget(_ client: ObjectIdentifier) {
        if request?.requester == client { request?.requester = nil }
        if next?.requester == client { next?.requester = nil }
        clientsOwedTheSize.remove(client)
    }
}
