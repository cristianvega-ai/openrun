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

private let nowhere = NSRange(location: NSNotFound, length: 0)

@MainActor @Suite struct TextInputOfViewTests {
    private func makeView() throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, delegate)
    }

    @Test func markedTextIsDrawnAndAnInsertEndsItAndSendsTheText() throws {
        let (view, delegate) = try makeView()
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: nowhere)
        #expect(view.hasMarkedText() && view.markedRange() == NSRange(location: 0, length: 3))
        #expect(view.renderer.markedText == "にほん" && delegate.takeSent() == "")
        view.setMarkedText(NSAttributedString(string: "日本"), selectedRange: nowhere, replacementRange: nowhere)
        #expect(view.renderer.markedText == "日本")
        view.insertText("日本", replacementRange: nowhere)
        #expect(!view.hasMarkedText() && view.markedRange() == nowhere && view.renderer.markedText == nil)
        #expect(delegate.takeSent() == "日本")
    }

    @Test func unmarkingDropsTheTextAndACommandOutsideAKeyDoesNothing() throws {
        let (view, delegate) = try makeView()
        view.setMarkedText("ㅎ", selectedRange: nowhere, replacementRange: nowhere)
        view.unmarkText()
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(!view.hasMarkedText() && view.renderer.markedText == nil && delegate.takeSent() == "")
        #expect(view.selectedRange() == nowhere && view.attributedSubstring(forProposedRange: nowhere, actualRange: nil) == nil)
    }
}
