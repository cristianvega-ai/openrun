import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionProcess

/// A program chooses every byte of its output, and one trap ends every
/// session. So this feeds many random and broken byte strings through the
/// path of a session's output: the prompt tracker and its terminal, the
/// events of the terminal, the scanner of kitty, the title and the bounded
/// text of the facts. The seed is fixed, so a failure repeats.
@Suite struct RandomOutputTests {
    /// SplitMix64: a small generator that gives the same numbers for a seed.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    static let seed: UInt64 = 0x0E2_2026_1110
    static let templates = [
        "\u{1B}]99;i=1:d=0:p=title;Tests\u{1B}\\", "\u{1B}]99;i=1:p=body:e=1;RG9uZSDinJM=\u{07}", "\u{1B}]99;=:==:x=;y\u{1B}\\",
        "\u{1B}]9;Build done\u{07}", "\u{1B}]9;4;1;50\u{07}", "\u{1B}]777;notify;Claude Code;Waiting\u{1B}\\",
        "\u{1B}]2;title \u{202E}\u{1B}\\", "\u{1B}]0;é\u{07}", "\u{1B}]133;A\u{07}", "\u{1B}]133;C\u{07}",
        "\u{1B}[0m\u{1B}[27m\u{1B}[24m\u{1B}[J% ", "\u{1B}[?2004h", "\u{1B}[?2004l", "\u{07}", "line\r\n", "\u{1B}[?1049h",
    ].map { Array($0.utf8) }

    static func mutated(_ bytes: [UInt8], using generator: inout SeededGenerator) -> [UInt8] {
        var result = bytes
        for _ in 0..<Int.random(in: 0...4, using: &generator) where !result.isEmpty {
            let index = Int.random(in: 0..<result.count, using: &generator)
            switch Int.random(in: 0..<4, using: &generator) {
            case 0: result[index] ^= UInt8.random(in: 1...255, using: &generator)
            case 1: result.remove(at: index)
            case 2: result.insert(contentsOf: result[index...].prefix(Int.random(in: 1...8, using: &generator)), at: index)
            default: result.insert(UInt8.random(in: 0...255, using: &generator), at: index)
            }
        }
        return result
    }

    static func randomOutput(using generator: inout SeededGenerator) -> [UInt8] {
        var output: [UInt8] = []
        for _ in 0..<Int.random(in: 1...6, using: &generator) {
            if Bool.random(using: &generator) {
                output += mutated(templates.randomElement(using: &generator) ?? [], using: &generator)
            } else {
                output += (0..<Int.random(in: 0...40, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) }
            }
        }
        return output
    }

    // A trap ends the test process before any message, so the name of the
    // test, which the run prints first, holds the seed.
    @Test("Random output never stops the session (seed 0x0E220261110)")
    func randomOutputNeverStopsTheSession() throws {
        var generator = SeededGenerator(state: Self.seed)
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 10), scrollbackLimit: 100)
        let prompts = ShellPromptTracker(terminal: terminal)
        let events = TerminalEvents()
        try terminal.setEventHandler(events.handler)
        var scanner = KittyNotificationScanner()
        var (titles, notifications) = (0, 0)
        for _ in 0..<50_000 {
            let output = Self.randomOutput(using: &generator)
            // Pieces split at random places, as the pseudo terminal reads them.
            var start = 0
            while start < output.count {
                let end = min(output.count, start + Int.random(in: 1...32, using: &generator))
                prompts.write(output[start..<end])
                if let text = scanner.notification(in: output[start..<end]) { events.note(notification: text) }
                if events.titleChanged { titles += SessionSummary.boundedText(terminal.title).isEmpty ? 0 : 1 }
                notifications += events.notification.map(SessionSummary.boundedText) == nil ? 0 : 1
                _ = prompts.prompt
                events.reset()
                start = end
            }
        }
        // The broken copies must still reach the code that reads them.
        #expect(titles > 1000 && notifications > 1000, "seed \(Self.seed): \(titles) titles, \(notifications) notifications")
    }
}
