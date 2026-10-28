import TerminalEmulation
import Testing
@testable import TerminalView

@Suite struct OrderedOutputTests {
    @Test func outputAndSizesStayInOrderAfterManyEvents() {
        let queue = TerminalOutputQueue()
        for number in 0..<2049 {
            queue.append(.bytes([UInt8(number % 256)]))
            if number == 1024 { queue.append(.size(TerminalSize(columns: 8, rows: 3), tellsDelegate: false)) }
        }
        for number in 0..<2049 {
            if number == 1025 {
                guard case .size(let grid, let tellsDelegate)? = queue.first else {
                    Issue.record("The size marker is missing.")
                    return
                }
                #expect(grid == TerminalSize(columns: 8, rows: 3) && !tellsDelegate)
                queue.removeFirst()
            }
            guard case .bytes(let bytes)? = queue.first else {
                Issue.record("The output is missing.")
                return
            }
            #expect(bytes == [UInt8(number % 256)])
            queue.removeFirst()
        }
        if case .some = queue.first { Issue.record("The queue is not empty.") }
        queue.append(.bytes([42]))
        guard case .bytes(let bytes)? = queue.first else {
            Issue.record("The queue cannot be used again.")
            return
        }
        #expect(bytes == [42])
    }
}
