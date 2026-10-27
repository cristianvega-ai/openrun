import Testing
@testable import TerminalEmulation

@Suite struct KeyEventTests {
    @Test func modifiersKeepTheBitsOfLibghosttyVt() {
        let all: [KeyModifiers] = [
            .shift, .control, .alternate, .superKey, .capsLock, .numberLock,
            .rightShift, .rightControl, .rightAlternate, .rightSuperKey,
        ]
        #expect(all.reduce(KeyModifiers()) { $0.union($1) }.rawValue.nonzeroBitCount == all.count)
    }

    @Test func aKeyEventKeepsItsFields() {
        let event = KeyEvent(
            action: .repeated, key: .b, modifiers: [.alternate, .rightAlternate],
            text: "b", unshiftedScalar: "b"
        )
        #expect(event.action == .repeated && event.key == .b)
        #expect(event.modifiers.contains(.rightAlternate))
        #expect(event.consumedModifiers.isEmpty && !event.isComposing)
        #expect(event.text == "b" && event.unshiftedScalar == "b")
    }
}

@Suite struct KeyEncoderTests {
    private func bytes(
        _ event: KeyEvent, after output: String = "", option: KeyEncoder.OptionAsAlternate = .never
    ) throws -> String {
        let terminal = try makeTerminal()
        terminal.write(output)
        let encoder = try KeyEncoder()
        encoder.update(from: terminal, optionAsAlternate: option)
        return String(decoding: try encoder.encode(event), as: UTF8.self)
    }

    @Test func legacyAndKittyKeys() throws {
        let escape = KeyEvent(action: .press, key: .escape)
        #expect(try bytes(escape) == "\u{1B}")
        #expect(try bytes(escape, after: "\u{1B}[>1u") == "\u{1B}[27u")
        #expect(try bytes(KeyEvent(action: .press, key: .c, modifiers: .control, unshiftedScalar: "c")) == "\u{03}")
        #expect(try bytes(KeyEvent(action: .press, key: .arrowUp), after: "\u{1B}[?1h") == "\u{1B}OA")
    }

    @Test func onlyTheLeftOptionKeyActsAsAlt() throws {
        let left = KeyEvent(action: .press, key: .b, modifiers: .alternate, text: "b", unshiftedScalar: "b")
        let right = KeyEvent(
            action: .press, key: .g, modifiers: [.alternate, .rightAlternate], consumedModifiers: .alternate, text: "©"
        )
        #expect(try bytes(left, option: .leftOnly) == "\u{1B}b")
        #expect(try bytes(right, option: .leftOnly) == "©")
    }
}
