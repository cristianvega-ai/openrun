import Foundation
import TerminalEmulation

/// Keeps the output that has not been parsed, and gives it to a terminal in
/// pieces. A program can write output faster than a view draws. A time limit
/// for each turn lets drawing and input run between turns, so a flood of
/// output does not hold the main thread.
final class OutputParser {
    /// The most bytes that one call of `Terminal.write` gets.
    let pieceSize: Int
    private let queue = TerminalOutputQueue()
    private var offset = 0
    private var isParsing = false
    private var discardsAfterParse = false
    var onSize: ((TerminalSize, _ tellsDelegate: Bool, _ keeping: PromptKeeping) -> Void)?

    init(pieceSize: Int = 64 * 1024) {
        self.pieceSize = pieceSize
    }

    var hasPendingOutput: Bool { queue.first != nil }

    func append(_ output: some ContiguousBytes, completion: (@Sendable () -> Void)? = nil) {
        output.withUnsafeBytes { queue.append(.bytes(Array($0)), completion: completion) }
    }

    /// Applies a size after all output that came before it.
    func append(size: TerminalSize, tellsDelegate: Bool, keeping: PromptKeeping = .nothing, completion: (@Sendable () -> Void)? = nil) {
        queue.append(.size(size, tellsDelegate: tellsDelegate, keeping: keeping), completion: completion)
    }

    /// A closed view releases its pending output and its admission slots.
    func discard() {
        if isParsing { discardsAfterParse = true; return }
        while queue.first != nil { queue.removeFirst() }
        offset = 0
    }

    /// Parses pieces until the budget is used. A turn always parses one piece,
    /// even with a budget of no time, so the output always moves on.
    ///
    /// - Returns: `true` when output is left for another turn.
    func parse(into terminal: Terminal, budget: ParseBudget) -> Bool {
        precondition(!isParsing)
        isParsing = true
        repeat {
            guard let event = queue.first else { break }
            switch event {
            case .bytes(let bytes):
                let end = min(offset + pieceSize, bytes.count)
                terminal.write(bytes[offset..<end])
                offset = end
                if offset == bytes.count { queue.removeFirst(); offset = 0 }
            case .size(let size, let tellsDelegate, let keeping):
                guard let onSize else { preconditionFailure("The size has no handler.") }
                onSize(size, tellsDelegate, keeping)
                queue.removeFirst()
            }
        } while hasPendingOutput && !budget.isUsed && !discardsAfterParse
        isParsing = false
        if discardsAfterParse { discardsAfterParse = false; discard() }
        return hasPendingOutput
    }
}
