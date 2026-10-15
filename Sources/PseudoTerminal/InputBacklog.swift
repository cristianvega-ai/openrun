struct InputBacklog {
    /// What happened to typed input.
    enum Outcome: Sendable {
        /// The bytes are in the backlog. The terminal takes them in order.
        case taken
        /// The program ended, or closed its terminal, first.
        case programEnded
        /// The owner withdrew the input first.
        case withdrawn
    }

    typealias Completion = @Sendable (Outcome) -> Void

    /// A completion to call once the books are in order.
    struct Notice {
        let completion: Completion
        let outcome: Outcome

        func deliver() {
            completion(outcome)
        }
    }

    /// Typed input waits for room past this many bytes in the backlog. A
    /// single piece that is larger waits for an empty backlog.
    static let typedLimit = 8 * 1024 * 1024
    /// Answers past this many bytes make `answersAreWithinLimit` false.
    static let answerLimit = 1 * 1024 * 1024

    private struct Piece {
        var bytes: ArraySlice<UInt8>
        let isAnswer: Bool
        /// Nil for answers and for bytes that stay without their owner.
        let owner: ObjectIdentifier?
    }

    /// Input behind typed input that did not fit. Typed input waits for room.
    /// An answer waits only for the input in front of it.
    private struct WaitingInput {
        let bytes: [UInt8]
        /// Nil for an answer.
        let owner: ObjectIdentifier?
        let staysWithoutOwner: Bool
        /// Nil for an answer, which nobody waits for.
        let completion: Completion?

        var isAnswer: Bool { owner == nil }
    }

    /// Each piece keeps its own storage, so writing the front costs nothing
    /// for the bytes behind it.
    private var pieces: [Piece] = []
    /// Whether some bytes of the front piece went out. A piece that started
    /// goes out whole, so the program never gets half of a key sequence.
    private var frontHasStarted = false
    private var waiting: [WaitingInput] = []
    private(set) var pendingByteCount = 0
    /// Answers in the backlog and answers that wait behind typed input.
    private(set) var pendingAnswerByteCount = 0
    /// Set when the program ended or closed its terminal. No input goes in.
    private(set) var isClosed = false

    var isEmpty: Bool { pieces.isEmpty }
    var hasWaitingInput: Bool { !waiting.isEmpty }
    var answersAreWithinLimit: Bool { pendingAnswerByteCount <= Self.answerLimit }

    /// The bytes that go to the terminal next.
    var front: ArraySlice<UInt8>? { pieces.first?.bytes }

    /// Puts typed input behind all earlier input. Call `admitWaiting` next.
    /// Returns a notice at once when no input can go in any more.
    mutating func addTyped(_ bytes: [UInt8], owner: ObjectIdentifier, staysWithoutOwner: Bool, completion: @escaping Completion) -> [Notice] {
        guard !isClosed else { return [Notice(completion: completion, outcome: .programEnded)] }
        waiting.append(WaitingInput(bytes: bytes, owner: owner, staysWithoutOwner: staysWithoutOwner, completion: completion))
        return []
    }

    /// Moves input that waits into the backlog: typed input while it fits,
    /// and an answer as soon as the input in front of it is in.
    mutating func admitWaiting() -> [Notice] {
        var notices: [Notice] = []
        while let next = waiting.first,
              next.isAnswer || pendingByteCount == 0 || pendingByteCount + next.bytes.count <= Self.typedLimit {
            waiting.removeFirst()
            if !next.bytes.isEmpty {
                let owner = next.staysWithoutOwner ? nil : next.owner
                pieces.append(Piece(bytes: next.bytes[...], isAnswer: next.isAnswer, owner: owner))
                pendingByteCount += next.bytes.count
            }
            if let completion = next.completion {
                notices.append(Notice(completion: completion, outcome: .taken))
            }
        }
        return notices
    }
}
