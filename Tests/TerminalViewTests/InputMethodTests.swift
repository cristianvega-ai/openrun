import AppKit
import Testing
@testable import TerminalView

@Suite struct TextInputStateTests {
    @Test func aKeyKeepsItsCommittedTextsAndCommandsInOrder() {
        var state = TextInputState()
        state.beginKey()
        state.mark("にほん")
        #expect(state.hasMarkedText)
        let waits = state.insert("日本")
        #expect(waits)
        state.record(#selector(NSResponder.deleteBackward(_:)))
        #expect(!state.hasMarkedText)
        let key = state.endKey()
        #expect(key.texts == ["日本"] && key.commands == [#selector(NSResponder.deleteBackward(_:))])
        #expect(state.endKey().texts.isEmpty)
    }

    @Test func textBetweenKeysIsNotKept() {
        var state = TextInputState()
        state.mark("zhong")
        let waits = state.insert("中")
        #expect(!waits)
        state.record(#selector(NSResponder.insertNewline(_:)))
        #expect(!state.hasMarkedText && state.endKey().texts.isEmpty)
    }

    @Test func unmarkEndsTheMarkedTextWithoutAText() {
        var state = TextInputState()
        state.beginKey()
        state.mark("ㅎ")
        state.unmark()
        #expect(!state.hasMarkedText && state.endKey().texts.isEmpty)
    }
}
