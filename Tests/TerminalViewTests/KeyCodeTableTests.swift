import Carbon.HIToolbox
import TerminalEmulation
import Testing
@testable import TerminalView

@Suite struct KeyCodeTableTests {
    @Test(arguments: [
        (kVK_ANSI_A, PhysicalKey.a), (kVK_ANSI_Z, .z), (kVK_ANSI_0, .digit0), (kVK_ANSI_Slash, .slash),
        (kVK_Return, .enter), (kVK_Delete, .backspace), (kVK_ForwardDelete, .delete), (kVK_Escape, .escape),
        (kVK_UpArrow, .arrowUp), (kVK_F1, .f1), (kVK_F20, .f20), (kVK_ANSI_KeypadEnter, .numberPadEnter),
        (kVK_Option, .altLeft), (kVK_RightOption, .altRight), (kVK_Command, .metaLeft), (kVK_Help, .insert),
    ])
    func aKeyCodeGivesTheKeyAtItsPlace(keyCode: Int, key: PhysicalKey) {
        #expect(KeyCodeTable.physicalKey(forKeyCode: UInt16(keyCode)) == key)
    }

    @Test func aKeyCodeThatNoTableEntryNamesIsUnidentified() {
        #expect(KeyCodeTable.physicalKey(forKeyCode: UInt16(kVK_VolumeUp)) == .unidentified)
        #expect(KeyCodeTable.physicalKey(forKeyCode: 0xFFFF) == .unidentified)
    }

    @Test func noTwoKeyCodesGiveTheSameKey() {
        #expect(Set(KeyCodeTable.keys.values).count == KeyCodeTable.keys.count)
    }
}
