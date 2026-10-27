import AppKit
import Carbon.HIToolbox
import TerminalEmulation
import Testing
@testable import TerminalView

@Suite(.enabled(if: usLayoutIsCurrent)) struct KeyboardEventReaderTests {
    private typealias Bit = ModifierReader.DeviceBit

    private func read(_ event: NSEvent, text: String? = nil) -> KeyEvent {
        KeyboardEventReader.keyEvent(from: event, action: .press, text: text ?? KeyboardEventReader.layoutText(of: event))
    }

    @Test func aKeyHasTheTextOfTheLayoutAndItsUnshiftedCharacter() {
        let plain = read(keyEvent(kVK_ANSI_A))
        #expect(plain.key == .a && plain.text == "a" && plain.unshiftedScalar == "a" && plain.modifiers.isEmpty)
        let shifted = read(keyEvent(kVK_ANSI_A, .shift))
        #expect(shifted.text == "A" && shifted.unshiftedScalar == "a")
        #expect(shifted.modifiers == .shift && shifted.consumedModifiers == .shift)
    }

    @Test func controlAndCommandMakeNoTextAndConsumeNothing() {
        let control = read(keyEvent(kVK_ANSI_C, .control))
        #expect(control.text == "c" && control.modifiers == .control && control.consumedModifiers.isEmpty)
        let command = read(keyEvent(kVK_ANSI_C, .command))
        #expect(command.modifiers == .superKey && command.consumedModifiers.isEmpty)
    }

    @Test func theLeftOptionKeyIsAltAndTheRightOneMakesACharacter() {
        let left = read(keyEvent(kVK_ANSI_B, .option, deviceBits: Bit.leftOption))
        #expect(left.text == "b" && left.modifiers == .alternate && left.consumedModifiers.isEmpty)
        let right = read(keyEvent(kVK_ANSI_G, .option, deviceBits: Bit.rightOption))
        #expect(right.text == "©" && right.modifiers == [.alternate, .rightAlternate])
        #expect(right.consumedModifiers == [.alternate, .rightAlternate])
    }

    @Test func controlCharactersAndFunctionKeysAreNotText() {
        #expect(read(keyEvent(kVK_Return)).text == nil)
        #expect(read(keyEvent(kVK_Escape)).text == nil)
        #expect(read(keyEvent(kVK_UpArrow)).text == nil)
        #expect(KeyboardEventReader.encoderText("\u{7F}") == nil)
        #expect(KeyboardEventReader.encoderText("日本") == "日本")
    }
}

@MainActor @Suite(.enabled(if: usLayoutIsCurrent)) struct KeyDownTests {
    /// The view and the delegate that records what the view sends.
    func makeView() throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, delegate)
    }

    @Test func theKeysOfALegacyProgramGiveTheirOwnBytes() throws {
        let (view, delegate) = try makeView()
        let keys: [(String, NSEvent, String)] = [
            ("a", keyEvent(kVK_ANSI_A), "a"), ("Shift-a", keyEvent(kVK_ANSI_A, .shift), "A"),
            ("Control-c", keyEvent(kVK_ANSI_C, .control), "\u{03}"), ("Return", keyEvent(kVK_Return), "\r"),
            ("Escape", keyEvent(kVK_Escape), "\u{1B}"), ("Backspace", keyEvent(kVK_Delete), "\u{7F}"),
            ("Shift-Tab", keyEvent(kVK_Tab, .shift), "\u{1B}[Z"), ("Up", keyEvent(kVK_UpArrow), "\u{1B}[A"),
            ("Control-Left", keyEvent(kVK_LeftArrow, .control), "\u{1B}[1;5D"), ("F1", keyEvent(kVK_F1), "\u{1B}OP"),
            ("Forward Delete", keyEvent(kVK_ForwardDelete), "\u{1B}[3~"), ("Command-c", keyEvent(kVK_ANSI_C, .command), ""),
        ]
        for (name, event, bytes) in keys {
            view.keyDown(with: event)
            #expect(delegate.takeSent() == bytes, "\(name)")
        }
    }

    @Test func aProgramThatAsksForApplicationCursorKeysGetsTheirOtherBytes() throws {
        let (view, delegate) = try makeView()
        view.terminal.write("\u{1B}[?1h")
        view.keyDown(with: keyEvent(kVK_UpArrow))
        #expect(delegate.takeSent() == "\u{1B}OA")
    }
}
