import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@Suite struct ModifierReaderTests {
    private typealias Bit = ModifierReader.DeviceBit

    private func flags(_ flags: NSEvent.ModifierFlags, bits: UInt = 0) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: flags.rawValue | bits)
    }

    @Test func theDeviceBitsGiveTheSideOfEachModifier() {
        #expect(ModifierReader.modifiers(of: []) == [])
        #expect(ModifierReader.modifiers(of: flags(.shift, bits: Bit.leftShift)) == .shift)
        #expect(ModifierReader.modifiers(of: flags(.shift, bits: Bit.rightShift)) == [.shift, .rightShift])
        #expect(ModifierReader.modifiers(of: flags(.control, bits: Bit.rightControl)) == [.control, .rightControl])
        #expect(ModifierReader.modifiers(of: flags(.option, bits: Bit.rightOption)) == [.alternate, .rightAlternate])
        #expect(ModifierReader.modifiers(of: flags(.command, bits: Bit.rightCommand)) == [.superKey, .rightSuperKey])
        #expect(ModifierReader.modifiers(of: flags(.command, bits: Bit.leftCommand)) == .superKey)
    }

    @Test func aModifierWithNoDeviceBitIsTheLeftKey() {
        #expect(ModifierReader.modifiers(of: [.option, .capsLock]) == [.alternate, .capsLock])
        #expect(ModifierReader.isLeftOption(.option))
    }

    @Test func theRightOptionKeyWinsWhenBothAreDown() {
        #expect(ModifierReader.isLeftOption(flags(.option, bits: Bit.leftOption)))
        #expect(!ModifierReader.isLeftOption(flags(.option, bits: Bit.rightOption)))
        #expect(!ModifierReader.isLeftOption(flags(.option, bits: Bit.leftOption | Bit.rightOption)))
        #expect(!ModifierReader.isLeftOption([]))
    }

    @Test func theLayoutDoesNotSeeTheLeftOptionKey() {
        let left = flags([.option, .shift], bits: Bit.leftOption)
        #expect(ModifierReader.translationFlags(left) == [.shift])
        let right = flags(.option, bits: Bit.rightOption)
        #expect(ModifierReader.translationFlags(right) == right)
    }
}
