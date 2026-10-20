/// Input on its way to a program, in the order it goes to the terminal.
///
/// It has two parts. The backlog holds the bytes that the terminal takes as
/// fast as the program reads. Typed input that does not fit waits for room,
/// in the order it was typed. The backlog holds at most `typedInputLimit` bytes
/// before typed input waits, so a program that never reads cannot make the
/// session process grow. Answers to the program's queries never wait for room,
/// because a terminal must not wait while it parses output. An answer goes
/// behind typed input that already waits, as a real terminal sends its bytes
/// in the order it made them, and joins the backlog together with that input.
///
/// Typed input has an owner. The owner can withdraw its input that has not
/// gone to the terminal yet, so a client that leaves holds no memory. Bytes
/// marked to stay without their owner leave only the waiting part: they are
/// text that a client was told has arrived.
///
/// The type only keeps the books. `PseudoTerminal` keeps one on its queue,
/// writes the bytes, and calls the completions that the methods return.
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

    /// The standard `typedInputLimit`.
    static let typedLimit = 8 * 1024 * 1024
    /// Answers past this many bytes make `answersAreWithinLimit` false.
    static let answerLimit = 1 * 1024 * 1024

    /// Typed input waits for room past this many bytes in the backlog. A
    /// single piece that is larger waits for an empty backlog.
    let typedInputLimit: Int

    init(typedInputLimit: Int = InputBacklog.typedLimit) {
        self.typedInputLimit = typedInputLimit
    }

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

    /// A first-in first-out queue whose start moves up when the front goes,
    /// so taking from the front does not move the elements behind it. The
    /// unused head of the storage is dropped once it is half of the storage,
    /// which keeps the cost of each removal constant on average.
    private struct FrontQueue<Element> {
        private var storage: [Element] = []
        private var start = 0

        var isEmpty: Bool { start == storage.count }
        var first: Element? { isEmpty ? nil : storage[start] }
        /// The elements from the front to the back.
        var elements: ArraySlice<Element> { storage[start...] }

        init(_ elements: [Element] = []) {
            storage = elements
        }

        mutating func append(_ element: Element) {
            storage.append(element)
        }

        mutating func replaceFirst(with element: Element) {
            storage[start] = element
        }

        mutating func removeFirst() {
            start += 1
            if start == storage.count {
                removeAll()
            } else if start >= 64, start * 2 >= storage.count {
                storage.removeFirst(start)
                start = 0
            }
        }

        mutating func removeAll() {
            storage.removeAll()
            start = 0
        }
    }

    /// Each piece keeps its own storage, so writing the front costs nothing
    /// for the bytes behind it.
    private var pieces = FrontQueue<Piece>()
    /// Whether some bytes of the front piece went out. A piece that started
    /// goes out whole, so the program never gets half of a key sequence.
    private var frontHasStarted = false
    private var waiting = FrontQueue<WaitingInput>()
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

    /// Puts an answer behind all earlier input. It goes into the backlog at
    /// once, even past the limit, unless typed input waits for room. Then it
    /// waits behind that input and goes in right after it, also past the
    /// limit. Either way it counts toward `answerLimit` at once.
    mutating func addAnswer(_ bytes: [UInt8]) {
        guard !isClosed, !bytes.isEmpty else { return }
        pendingAnswerByteCount += bytes.count
        if waiting.isEmpty {
            pieces.append(Piece(bytes: bytes[...], isAnswer: true, owner: nil))
            pendingByteCount += bytes.count
        } else {
            waiting.append(WaitingInput(bytes: bytes, owner: nil, staysWithoutOwner: false, completion: nil))
        }
    }

    /// Moves input that waits into the backlog: typed input while it fits,
    /// and an answer as soon as the input in front of it is in.
    mutating func admitWaiting() -> [Notice] {
        var notices: [Notice] = []
        while let next = waiting.first,
              next.isAnswer || pendingByteCount == 0 || pendingByteCount + next.bytes.count <= typedInputLimit {
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

    /// Records that the terminal took this many bytes from the front.
    mutating func removeFromFront(_ count: Int) {
        guard count > 0, var piece = pieces.first else { return }
        piece.bytes = piece.bytes.dropFirst(count)
        pendingByteCount -= count
        if piece.isAnswer { pendingAnswerByteCount -= count }
        if piece.bytes.isEmpty {
            pieces.removeFirst()
            frontHasStarted = false
        } else {
            pieces.replaceFirst(with: piece)
            frontHasStarted = true
        }
    }

    /// Removes the owner's input that has not gone to the terminal yet: the
    /// input that waits, and the pieces in the backlog that have not started.
    mutating func withdraw(owner: ObjectIdentifier) -> [Notice] {
        var notices: [Notice] = []
        // An answer has no owner, so it stays and moves up behind the rest.
        waiting = FrontQueue(waiting.elements.filter { input in
            guard input.owner == owner, let completion = input.completion else { return true }
            notices.append(Notice(completion: completion, outcome: .withdrawn))
            return false
        })
        // A front piece that started stays, so `frontHasStarted` still
        // describes the front. A front piece that goes had not started.
        var kept: [Piece] = []
        for (index, piece) in pieces.elements.enumerated() {
            if piece.owner == owner, !(index == 0 && frontHasStarted) {
                pendingByteCount -= piece.bytes.count
            } else {
                kept.append(piece)
            }
        }
        pieces = FrontQueue(kept)
        return notices
    }

    /// Ends all input: the backlog goes, and all typed input that waits fails.
    mutating func close() -> [Notice] {
        isClosed = true
        pieces.removeAll()
        frontHasStarted = false
        pendingByteCount = 0
        pendingAnswerByteCount = 0
        let notices = waiting.elements.compactMap { input in
            input.completion.map { Notice(completion: $0, outcome: .programEnded) }
        }
        waiting.removeAll()
        return notices
    }
}
