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

    @Test func theLeftOptionKeyIsAltAndTheRightOptionKeyTypesACharacter() throws {
        let (view, delegate) = try makeView()
        let left = ModifierReader.DeviceBit.leftOption, right = ModifierReader.DeviceBit.rightOption
        let keys: [(String, NSEvent, String)] = [
            ("left Option-b", keyEvent(kVK_ANSI_B, .option, deviceBits: left), "\u{1B}b"),
            ("left Option-Shift-b", keyEvent(kVK_ANSI_B, [.option, .shift], deviceBits: left), "\u{1B}B"),
            ("left Option-Backspace", keyEvent(kVK_Delete, .option, deviceBits: left), "\u{1B}\u{7F}"),
            ("left Option-period", keyEvent(kVK_ANSI_Period, .option, deviceBits: left), "\u{1B}."),
            ("right Option-g", keyEvent(kVK_ANSI_G, .option, deviceBits: right), "©"),
            ("right Option-2", keyEvent(kVK_ANSI_2, .option, deviceBits: right), "™"),
        ]
        for (name, event, bytes) in keys {
            view.keyDown(with: event)
            #expect(delegate.takeSent() == bytes, "\(name)")
        }
        view.terminal.write("\u{1B}[>1u")
        view.keyDown(with: keys[0].1)
        view.keyDown(with: keys[4].1)
        #expect(delegate.takeSent() == "\u{1B}[98;3u©")
    }

    @Test func theOwnerChoosesWhichOptionKeysAreAlt() throws {
        let (view, delegate) = try makeView()
        let left = ModifierReader.DeviceBit.leftOption, right = ModifierReader.DeviceBit.rightOption
        view.optionKeyRule = .both
        view.keyDown(with: keyEvent(kVK_ANSI_B, .option, deviceBits: right))
        view.keyDown(with: keyEvent(kVK_ANSI_B, .option, deviceBits: left))
        #expect(delegate.takeSent() == "\u{1B}b\u{1B}b")
        view.optionKeyRule = .neither
        view.keyDown(with: keyEvent(kVK_ANSI_G, .option, deviceBits: left))
        view.keyDown(with: keyEvent(kVK_ANSI_G, .option, deviceBits: right))
        #expect(delegate.takeSent() == "©©")
    }

    @Test func aKeyThatSendsBytesMovesTheViewportToTheBottom() throws {
        let (view, delegate) = try makeView()
        view.terminal.write(String(repeating: "line\r\n", count: 100))
        view.terminal.scrollViewport(.byRows(-10))
        view.keyDown(with: keyEvent(kVK_ANSI_C, .command))
        #expect(!view.terminal.isViewportAtBottom)
        view.keyDown(with: keyEvent(kVK_ANSI_A))
        #expect(view.terminal.isViewportAtBottom && delegate.takeSent() == "a")
    }

    @Test func releasesAndModifierKeysGoOnlyToAProgramThatAsksForThem() throws {
        let (view, delegate) = try makeView()
        let release = keyEvent(kVK_ANSI_A, type: .keyUp)
        let shiftDown = keyEvent(kVK_Shift, .shift, deviceBits: ModifierReader.DeviceBit.leftShift, type: .flagsChanged)
        let shiftUp = keyEvent(kVK_Shift, type: .flagsChanged)
        view.keyUp(with: release)
        view.flagsChanged(with: shiftDown)
        view.flagsChanged(with: shiftUp)
        #expect(delegate.takeSent() == "")
        view.terminal.write("\u{1B}[>11u")
        view.keyDown(with: keyEvent(kVK_ANSI_A))
        view.keyUp(with: release)
        view.flagsChanged(with: shiftDown)
        view.flagsChanged(with: shiftUp)
        #expect(delegate.takeSent() == "\u{1B}[97u\u{1B}[97;1:3u\u{1B}[57441;2u\u{1B}[57441;1:3u")
    }
}
