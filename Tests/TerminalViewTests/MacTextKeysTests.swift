import AppKit
import Carbon.HIToolbox
import Testing
@testable import TerminalView

@MainActor @Suite(.enabled(if: usLayoutIsCurrent)) struct MacTextKeysTests {
    private typealias Bit = ModifierReader.DeviceBit

    private func makeView() throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, delegate)
    }

    private let keys: [(String, NSEvent, String)] = [
        ("Command-Left", keyEvent(kVK_LeftArrow, [.command, .function, .numericPad]), "\u{01}"),
        ("Command-Right", keyEvent(kVK_RightArrow, [.command, .function, .numericPad]), "\u{05}"),
        ("Command-Backspace", keyEvent(kVK_Delete, .command), "\u{15}"),
        ("left Option-Left", keyEvent(kVK_LeftArrow, [.option, .function, .numericPad], deviceBits: Bit.leftOption), "\u{1B}b"),
        ("right Option-Right", keyEvent(kVK_RightArrow, [.option, .function, .numericPad], deviceBits: Bit.rightOption), "\u{1B}f"),
        ("left Option-Backspace", keyEvent(kVK_Delete, .option, deviceBits: Bit.leftOption), "\u{1B}\u{7F}"),
        ("right Option-Backspace", keyEvent(kVK_Delete, .option, deviceBits: Bit.rightOption), "\u{1B}\u{7F}"),
    ]

    @Test func theMacKeysForTextSendTheKeysOfTheLineEditor() throws {
        let (view, delegate) = try makeView()
        for rule in OptionKeyRule.allCases {
            view.optionKeyRule = rule
            for (name, event, bytes) in keys {
                view.keyDown(with: event)
                #expect(delegate.takeSent() == bytes, "\(name) \(rule)")
            }
        }
        // Shift selects in the text of a Mac and has no meaning here, so the key goes as it is.
        view.keyDown(with: keyEvent(kVK_LeftArrow, [.command, .shift, .function, .numericPad]))
        #expect(delegate.takeSent() != "\u{01}")
        view.keyDown(with: keyEvent(kVK_LeftArrow, [.function, .numericPad]))
        #expect(delegate.takeSent() == "\u{1B}[D")
    }

    @Test func aProgramWithTheKittyKeyboardProtocolGetsTheKeysAsItAsked() throws {
        let (view, delegate) = try makeView()
        view.terminal.write("\u{1B}[>1u")
        view.keyDown(with: keys[0].1)
        view.keyDown(with: keys[3].1)
        #expect(delegate.takeSent() == "\u{1B}[1;9D\u{1B}[1;3D")
    }

    @Test func markedTextKeepsTheKeyForTheInputMethod() throws {
        let (view, delegate) = try makeView()
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        _ = view.keyboard.bytes(forKeyDown: keys[3].1) { _ in }
        #expect(delegate.takeSent() == "" && view.hasMarkedText())
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func commandLeftPassesTheMenuAndReachesTheProgram() throws {
        let (view, delegate) = try makeView()
        let window = showFocused(view)
        defer { window.close() }
        view.commandMenu = NSMenu()
        #expect(view.performKeyEquivalent(with: keys[0].1) && view.performKeyEquivalent(with: keys[2].1))
        #expect(delegate.takeSent() == "\u{01}\u{15}")
    }
}
