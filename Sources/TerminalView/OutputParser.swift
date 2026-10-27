import Foundation
import TerminalEmulation

/// Keeps the output that has not been parsed, and gives it to a terminal in
/// pieces. A program can write output faster than a view draws. A time limit
/// for each turn lets drawing and input run between turns, so a flood of
/// output does not hold the main thread.
final class OutputParser {
    /// The most bytes that one call of `Terminal.write` gets.
    let pieceSize: Int
    private var bytes: [UInt8] = []
    private var offset = 0

    init(pieceSize: Int = 64 * 1024) {
        self.pieceSize = pieceSize
    }

    var hasPendingOutput: Bool { offset < bytes.count }

    func append(_ output: some ContiguousBytes) {
        output.withUnsafeBytes { bytes.append(contentsOf: $0) }
    }

    /// Parses pieces until the budget is used. A turn always parses one piece,
    /// even with a budget of no time, so the output always moves on.
    ///
    /// - Returns: `true` when output is left for another turn.
    func parse(into terminal: Terminal, budget: ParseBudget) -> Bool {
        repeat {
            let end = min(offset + pieceSize, bytes.count)
            terminal.write(bytes[offset..<end])
            offset = end
        } while hasPendingOutput && !budget.isUsed
        if !hasPendingOutput {
            bytes.removeAll(keepingCapacity: true)
            offset = 0
        } else if offset >= 1 << 20 {
            // The parsed part would grow without limit under a long flood.
            bytes.removeFirst(offset)
            offset = 0
        }
        return hasPendingOutput
    }
}
