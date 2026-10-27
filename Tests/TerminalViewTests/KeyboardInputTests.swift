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
