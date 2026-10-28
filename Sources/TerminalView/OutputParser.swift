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

    init(pieceSize: Int = 64 * 1024) {
        self.pieceSize = pieceSize
    }

    var hasPendingOutput: Bool { queue.first != nil }

    func append(_ output: some ContiguousBytes) {
        output.withUnsafeBytes { queue.append(.bytes(Array($0))) }
    }

    /// Parses pieces until the budget is used. A turn always parses one piece,
    /// even with a budget of no time, so the output always moves on.
    ///
    /// - Returns: `true` when output is left for another turn.
    func parse(into terminal: Terminal, budget: ParseBudget) -> Bool {
        repeat {
            guard case .bytes(let bytes)? = queue.first else { break }
            let end = min(offset + pieceSize, bytes.count)
            terminal.write(bytes[offset..<end])
            offset = end
            if offset == bytes.count { queue.removeFirst(); offset = 0 }
        } while hasPendingOutput && !budget.isUsed
        return hasPendingOutput
    }
}
