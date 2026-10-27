import AppKit
import Carbon.HIToolbox
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

@MainActor @Suite struct CandidateWindowPlaceTests {
    @Test(.enabled(if: NSScreen.main != nil))
    func theInputMethodGetsTheCellOfTheCursorInScreenCoordinates() throws {
        let view = try TerminalView()
        let window = show(view)
        defer { window.close() }
        view.terminal.write("ab\r\ncd")
        let rect = view.firstRect(forCharacterRange: nowhere, actualRange: nil)
        let content = window.contentRect(forFrameRect: window.frame), cell = view.cellSize
        // The cursor is in column 2 of row 1. The bottom of the row is 2 rows under the padding.
        #expect(rect == NSRect(x: content.minX + view.gridPadding + 2 * cell.width, y: content.maxY - view.gridPadding - 2 * cell.height, width: cell.width, height: cell.height))
    }
}

@MainActor @Suite(.enabled(if: usLayoutIsCurrent)) struct KeyThroughInputMethodTests {
    private let rightOption = ModifierReader.DeviceBit.rightOption
    private let leftOption = ModifierReader.DeviceBit.leftOption

    /// Gives a key to the view while a fake input method answers as the text input system does.
    private func press(_ event: NSEvent, in view: TerminalView, delegate: RecordingDelegate, answer: (TerminalView, NSEvent) -> Void = { _, _ in }) -> String {
        view.sendTyped(view.keyboard.bytes(forKeyDown: event) { answer(view, $0) })
        return delegate.takeSent()
    }

    private func makeView() throws -> (TerminalView, RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, delegate)
    }

    @Test func aDeadKeyMakesMarkedTextAndTheNextKeySendsTheCharacter() throws {
        let (view, delegate) = try makeView()
        let first = press(keyEvent(kVK_ANSI_E, .option, deviceBits: rightOption), in: view, delegate: delegate) { view, _ in
            view.setMarkedText("´", selectedRange: nowhere, replacementRange: nowhere)
        }
        #expect(first == "" && view.renderer.markedText == "´")
        let second = press(keyEvent(kVK_ANSI_E), in: view, delegate: delegate) { view, _ in view.insertText("é", replacementRange: nowhere) }
        #expect(second == "é" && view.renderer.markedText == nil)
    }

    @Test func aCommandAfterCommittedTextSendsTheKeyToo() throws {
        let (view, delegate) = try makeView()
        view.setMarkedText("˜", selectedRange: nowhere, replacementRange: nowhere)
        let bytes = press(keyEvent(kVK_Delete), in: view, delegate: delegate) { view, _ in
            view.insertText("˜", replacementRange: nowhere)
            view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        }
        #expect(bytes == "˜\u{7F}")
    }

    @Test func aKeyThatTheInputMethodLeavesGoesThroughTheEncoder() throws {
        let (view, delegate) = try makeView()
        let a = press(keyEvent(kVK_ANSI_A), in: view, delegate: delegate) { view, _ in view.insertText("a", replacementRange: nowhere) }
        let control = press(keyEvent(kVK_ANSI_C, .control), in: view, delegate: delegate) { view, _ in view.doCommand(by: NSSelectorFromString("noop:")) }
        let up = press(keyEvent(kVK_UpArrow), in: view, delegate: delegate) { view, _ in view.doCommand(by: #selector(NSResponder.moveUp(_:))) }
        #expect([a, control, up] == ["a", "\u{03}", "\u{1B}[A"])
    }

    @Test func theInputMethodSeesTheLeftOptionKeyAsNoOptionKey() throws {
        let (view, delegate) = try makeView()
        var seen: NSEvent.ModifierFlags = []
        let bytes = press(keyEvent(kVK_ANSI_E, .option, deviceBits: leftOption), in: view, delegate: delegate) { view, event in
            seen = event.modifierFlags
            view.insertText(event.characters ?? "", replacementRange: nowhere)
        }
        #expect(!seen.contains(.option) && bytes == "\u{1B}e")
        let plain = keyEvent(kVK_ANSI_A)
        _ = press(plain, in: view, delegate: delegate) { _, event in #expect(event === plain) }
    }
}
