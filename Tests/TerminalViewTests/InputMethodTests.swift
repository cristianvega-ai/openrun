import AppKit
import Carbon.HIToolbox
import Testing
import TerminalEmulation
@testable import TerminalView

@Suite struct TextInputStateTests {
    @Test func aKeyKeepsItsCommittedTextsAndCommandsInOrder() {
        var state = TextInputState()
        state.beginKey()
        state.mark("にほん")
        #expect(state.hasMarkedText)
        let waits = state.insert("日本")
        #expect(waits == nil)
        state.record(#selector(NSResponder.deleteBackward(_:)))
        #expect(!state.hasMarkedText)
        let key = state.endKey()
        #expect(key.texts == ["日本"] && key.commands == [#selector(NSResponder.deleteBackward(_:))])
        #expect(state.endKey().texts.isEmpty)
    }

    @Test func textBetweenKeysIsNotKept() {
        var state = TextInputState()
        state.mark("zhong")
        let text = state.insert("中")
        #expect(text == "中")
        state.record(#selector(NSResponder.insertNewline(_:)))
        #expect(!state.hasMarkedText && state.endKey().texts.isEmpty)
    }

    @Test func aBareControlCharacterIsDroppedOnlyWhileTheTextIsMarked() {
        var state = TextInputState()
        state.beginKey()
        let kept = state.insert("\u{03}")
        state.mark("にほん")
        let dropped = state.insert("\u{03}\r")
        let text = state.insert("日\r")
        #expect(kept == nil && dropped == nil && text == nil)
        #expect(state.endKey().texts == ["\u{03}", "日\r"])
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

    @Test func theViewKeepsTheSelectedRangeAndExposesMarkedCharacters() throws {
        let (view, _) = try makeView()
        view.setMarkedText("あ😀e\u{301}", selectedRange: NSRange(location: 1, length: 2), replacementRange: nowhere)
        #expect(view.markedRange() == NSRange(location: 0, length: 5) && view.selectedRange() == NSRange(location: 1, length: 2))
        #expect(view.renderer.markedTextSelection == NSRange(location: 1, length: 2))
        var actual = nowhere
        let result = view.attributedSubstring(forProposedRange: NSRange(location: 2, length: 1), actualRange: &actual)
        #expect(result?.string == "😀" && actual == NSRange(location: 1, length: 2))
        view.setMarkedText("あ😀", selectedRange: NSRange(location: 2, length: 99), replacementRange: nowhere)
        #expect(view.selectedRange() == NSRange(location: 2, length: 1))
        view.setMarkedText("あ😀e\u{301}", selectedRange: NSRange(location: 1, length: 2), replacementRange: nowhere)
        view.rebuildRenderer(scale: 1)
        #expect(view.renderer.markedTextSelection == NSRange(location: 1, length: 2))
        view.insertText("日本", replacementRange: nowhere)
        #expect(view.selectedRange() == nowhere && view.renderer.markedTextSelection == nil)
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
    func aCandidateFollowsTheSelectedCharacterAcrossARow() throws {
        let view = try TerminalView()
        let window = show(view)
        defer { window.close() }
        try view.terminal.resize(to: TerminalSize(columns: 6, rows: 3))
        view.terminal.write("abcde")
        view.setMarkedText("日本😀", selectedRange: NSRange(location: 2, length: 0), replacementRange: nowhere)
        let cell = view.cellSize
        let rowStart = window.convertToScreen(view.convert(NSRect(x: view.gridPadding, y: view.bounds.height - view.gridPadding - 2 * cell.height, width: cell.width, height: cell.height), to: nil))
        var actual = nowhere
        let selected = view.firstRect(forCharacterRange: nowhere, actualRange: &actual)
        #expect(selected == rowStart.offsetBy(dx: 4 * cell.width, dy: 0) && actual == NSRange(location: 2, length: 2))
        let earlier = view.firstRect(forCharacterRange: NSRange(location: 1, length: 0), actualRange: &actual)
        #expect(earlier == rowStart.offsetBy(dx: 2 * cell.width, dy: 0) && actual == NSRange(location: 1, length: 1))
        let end = view.firstRect(forCharacterRange: NSRange(location: 4, length: 0), actualRange: &actual)
        #expect(end == rowStart.offsetBy(dx: 6 * cell.width, dy: 0) && actual == NSRange(location: 4, length: 0))
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func theInputMethodGetsTheCellOfTheCursorInScreenCoordinates() throws {
        let view = try TerminalView()
        let window = show(view)
        defer { window.close() }
        view.terminal.write("ab\r\ncd")
        let rectangle = view.firstRect(forCharacterRange: nowhere, actualRange: nil)
        let content = window.contentRect(forFrameRect: window.frame), cell = view.cellSize
        // The cursor is in column 2 of row 1. The bottom of the row is 2 rows under the padding.
        #expect(rectangle == NSRect(x: content.minX + view.gridPadding + 2 * cell.width, y: content.maxY - view.gridPadding - 2 * cell.height, width: cell.width, height: cell.height))
    }
}

@MainActor @Suite(.enabled(if: usLayoutIsCurrent)) struct ComposingKeyTests {
    @Test func aControlCharacterAndAModifierKeySendNothingWhileTheTextIsMarked() throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.terminal.write("\u{1B}[>11u")
        view.flagsChanged(with: keyEvent(kVK_Shift, .shift, deviceBits: ModifierReader.DeviceBit.leftShift, type: .flagsChanged))
        #expect(delegate.takeSent() == "\u{1B}[57441;2u")
        view.setMarkedText("ㅎ", selectedRange: nowhere, replacementRange: nowhere)
        view.flagsChanged(with: keyEvent(kVK_Shift, type: .flagsChanged))
        view.sendTyped(view.keyboard.bytes(forKeyDown: keyEvent(kVK_ANSI_C, .control)) { _ in view.insertText("\u{03}", replacementRange: nowhere) })
        #expect(delegate.takeSent() == "" && view.renderer.markedText == "ㅎ")
    }
}

@MainActor @Suite(.enabled(if: usLayoutIsCurrent)) struct InputSourceChangeTests {
    @Test func aKeyThatChangesTheInputSourceSendsNothing() throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        var source = "com.apple.keylayout.US"
        view.keyboard.layout = KeyboardLayoutWatch { source }
        func press(_ key: Int, _ change: String? = nil) -> String {
            view.sendTyped(view.keyboard.bytes(forKeyDown: keyEvent(key)) { _ in
                if let change { source = change }
                view.insertText("a", replacementRange: nowhere)
            })
            return delegate.takeSent()
        }
        #expect(press(kVK_ANSI_A) == "a")
        #expect(press(kVK_Space, "com.apple.inputmethod.Kotoeri.Japanese") == "")
        #expect(press(kVK_ANSI_A) == "a")
        #expect(KeyboardLayoutWatch().identifier() != nil)
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

    @Test func keysAndInputMethodCommitsStayKeysInBracketedPasteMode() throws {
        let (view, delegate) = try makeView()
        view.terminal.write("\u{1B}[?2004h")
        let a = press(keyEvent(kVK_ANSI_A), in: view, delegate: delegate) { view, _ in view.insertText("a", replacementRange: nowhere) }
        view.setMarkedText("にほん", selectedRange: nowhere, replacementRange: nowhere)
        let text = press(keyEvent(kVK_Return), in: view, delegate: delegate) { view, _ in view.insertText("日本", replacementRange: nowhere) }
        let control = press(keyEvent(kVK_ANSI_C, .control), in: view, delegate: delegate) { view, _ in view.doCommand(by: NSSelectorFromString("noop:")) }
        #expect([a, text, control] == ["a", "日本", "\u{03}"] && delegate.questions.isEmpty)
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

@MainActor @Suite struct ExternalInputMethodTests {
    @Test func externalTextUsesPasteEncodingAndClearsMarkedText() throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.insertText(NSAttributedString(string: "é😀e\u{301}"), replacementRange: nowhere)
        #expect(delegate.takeSent() == "é😀e\u{301}" && delegate.questions.isEmpty)

        view.terminal.write("\u{1B}[?2004h")
        view.setMarkedText("にほん", selectedRange: nowhere, replacementRange: nowhere)
        view.insertText(NSAttributedString(string: "日本😀\n次\u{1B}[201~"), replacementRange: nowhere)
        #expect(!view.hasMarkedText() && view.renderer.markedText == nil)
        #expect(delegate.takeSent() == "\u{1B}[200~日本😀\n次 [201~\u{1B}[201~" && delegate.questions.isEmpty)
    }

    @Test func externalLinesWaitForApprovalAndUseTheCurrentPasteMode() async throws {
        let view = try TerminalView()
        let delegate = PendingPasteDelegate()
        view.delegate = delegate
        let text = "echo a\necho b"

        view.insertText(text, replacementRange: nowhere)
        #expect(delegate.sent.isEmpty)
        await settle { delegate.questions.count == 1 }
        #expect(delegate.questions == [text] && delegate.sent.isEmpty)
        delegate.respond(false)
        await settle { delegate.responses == 1 }
        #expect(delegate.sent.isEmpty)

        view.insertText(text, replacementRange: nowhere)
        await settle { delegate.questions.count == 2 }
        #expect(delegate.sent.isEmpty)
        delegate.respond(true)
        await settle { delegate.responses == 2 }
        #expect(String(decoding: delegate.sent, as: UTF8.self) == "echo a\recho b")
        delegate.sent = []

        view.insertText(text, replacementRange: nowhere)
        await settle { delegate.questions.count == 3 }
        view.terminal.write("\u{1B}[?2004h")
        delegate.respond(true)
        await settle { delegate.responses == 3 }
        #expect(String(decoding: delegate.sent, as: UTF8.self) == "\u{1B}[200~echo a\necho b\u{1B}[201~")
    }

    @Test(arguments: ["\n", "\r", "\r\n"])
    func everyExternalLineBreakAsksWithoutBracketedPaste(lineBreak: String) async throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        let text = "one" + lineBreak + "two"
        view.insertText(text, replacementRange: nowhere)
        await settle { !delegate.questions.isEmpty }
        #expect(delegate.questions == [text] && delegate.sent.isEmpty)
    }

    @Test func externalControlTextWhileMarkedAndUnsafeTextWithoutAnOwnerSendNothing() async throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.setMarkedText("ㅎ", selectedRange: nowhere, replacementRange: nowhere)
        view.insertText("\u{03}\r", replacementRange: nowhere)
        #expect(view.hasMarkedText() && delegate.sent.isEmpty && delegate.questions.isEmpty)
        view.delegate = nil
        view.insertText("하\r다", replacementRange: nowhere)
        await settle(seconds: 0.05) { false }
        #expect(!view.hasMarkedText() && delegate.sent.isEmpty && delegate.questions.isEmpty)
    }

    @Test func approvalCannotSendToAChangedOrReattachedOwner() async throws {
        for external in [true, false] {
            let view = try TerminalView()
            let original = PendingPasteDelegate()
            let replacement = RecordingDelegate()
            view.delegate = original
            if external {
                view.insertText("first\nsecond", replacementRange: nowhere)
            } else {
                let pasteboard = FakePasteboard()
                pasteboard.text = "first\nsecond"
                view.pasteboard = pasteboard
                view.paste(nil)
            }
            await settle { original.questions.count == 1 }
            #expect(original.questions == ["first\nsecond"] && original.sent.isEmpty)
            view.delegate = replacement
            view.delegate = original
            original.respond(true)
            await settle { original.responses == 1 }
            #expect(original.responses == 1 && original.sent.isEmpty && replacement.sent.isEmpty)
        }
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func approvalCannotSendAfterTheWindowClosesOrTheViewMoves() async throws {
        for closesWindow in [true, false] {
            let view = try TerminalView()
            let delegate = PendingPasteDelegate()
            view.delegate = delegate
            let window = show(view)
            view.insertText("first\nsecond", replacementRange: nowhere)
            await settle { delegate.questions.count == 1 }
            #expect(delegate.questions == ["first\nsecond"] && delegate.sent.isEmpty)
            if closesWindow {
                window.close()
            } else {
                window.contentView = nil
                window.contentView = view
            }
            delegate.respond(true)
            await settle { delegate.responses == 1 }
            #expect(delegate.responses == 1 && delegate.sent.isEmpty)
            window.close()
        }
    }

    private final class PendingPasteDelegate: TerminalViewDelegate {
        var sent: [UInt8] = []
        var questions: [String] = []
        var responses = 0
        private var continuation: CheckedContinuation<Bool, Never>?

        func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize) {}
        func terminalView(_ view: TerminalView, didChangeTitle title: String) {}
        func terminalView(_ view: TerminalView, send bytes: [UInt8]) { sent += bytes }
        func terminalView(_ view: TerminalView, shouldPasteUnsafeText text: String) async -> Bool {
            questions.append(text)
            let answer = await withCheckedContinuation { continuation = $0 }
            responses += 1
            return answer
        }
        func respond(_ answer: Bool) {
            let pending = continuation
            continuation = nil
            pending?.resume(returning: answer)
        }
    }
}

/// Japanese, Chinese and Korean input methods, played call by call as they use `NSTextInputClient`.
/// The owner checks a real input method by hand at the review of the milestone.
@MainActor @Suite struct InputMethodStringTests {
    private enum Answer { case mark(String), insert(String) }

    /// Presses each key while a fake input method gives its answer. Gives the bytes that each key sent
    /// and the marked text that the renderer draws after it.
    private func play(_ steps: [(Int, Answer)]) throws -> (bytes: [String], marked: [String?]) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        var result: (bytes: [String], marked: [String?]) = ([], [])
        for (keyCode, answer) in steps {
            view.sendTyped(view.keyboard.bytes(forKeyDown: keyEvent(keyCode)) { _ in
                switch answer {
                case .mark(let text): view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: nowhere)
                case .insert(let text): view.insertText(text, replacementRange: nowhere)
                }
            })
            result.bytes.append(delegate.takeSent())
            result.marked.append(view.renderer.markedText)
        }
        return result
    }

    @Test func japaneseKanaAreMarkedAndTheKanjiAreCommitted() throws {
        let marks = ["ん", "に", "にh", "にほ", "にほn", "にほん", "日本"]
        let keys = [kVK_ANSI_N, kVK_ANSI_I, kVK_ANSI_H, kVK_ANSI_O, kVK_ANSI_N, kVK_ANSI_N, kVK_Space]
        let result = try play(zip(keys, marks).map { ($0, .mark($1)) } + [(kVK_Return, .insert("日本"))])
        #expect(result.marked == marks + [nil])
        #expect(result.bytes == Array(repeating: "", count: marks.count) + ["日本"])
    }

    @Test func chinesePinyinIsMarkedAndTheCharacterIsCommitted() throws {
        let marks = ["z", "zh", "zho", "zhon", "zhong"]
        let result = try play(zip([kVK_ANSI_Z, kVK_ANSI_H, kVK_ANSI_O, kVK_ANSI_N, kVK_ANSI_G], marks).map { ($0, .mark($1)) } + [(kVK_Space, .insert("中"))])
        #expect(result.marked == marks + [nil] && result.bytes == ["", "", "", "", "", "中"])
    }

    @Test func koreanJamoJoinIntoOneSyllable() throws {
        let result = try play([(kVK_ANSI_G, .mark("ㅎ")), (kVK_ANSI_K, .mark("하")), (kVK_ANSI_S, .mark("한")), (kVK_Space, .insert("한"))])
        #expect(result.marked == ["ㅎ", "하", "한", nil] && result.bytes == ["", "", "", "한"])
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func theListOfCandidatesStaysAtTheCursorWhileTheTextIsMarked() throws {
        let view = try TerminalView()
        let window = show(view)
        defer { window.close() }
        view.terminal.write("$ ")
        let before = view.firstRect(forCharacterRange: nowhere, actualRange: nil)
        view.setMarkedText("にほん", selectedRange: nowhere, replacementRange: nowhere)
        let after = view.firstRect(forCharacterRange: nowhere, actualRange: nil)
        #expect(after.minX == before.minX + 6 * view.cellSize.width && before.minX > window.frame.minX)
    }
}
