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
