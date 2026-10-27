import AppKit
import Carbon.HIToolbox
import Testing
@testable import TerminalView

@Suite(.enabled(if: usLayoutIsCurrent)) struct KeyEquivalentRouteTests {
    private func route(_ keyCode: Int, _ flags: NSEvent.ModifierFlags = [], hasMarkedText: Bool = false) -> KeyEquivalentRoute {
        KeyEquivalentRoute.route(for: keyEvent(keyCode, flags), hasMarkedText: hasMarkedText)
    }

    @Test func everyControlChordGoesToKeyDownOneTime() {
        #expect(route(kVK_ANSI_C, .control) == .keyDown)
        #expect(route(kVK_Return, .control) == .keyDown)
        #expect(route(kVK_ANSI_Slash, .control) == .keyDown)
        #expect(route(kVK_LeftArrow, [.control, .shift]) == .keyDown)
    }

    @Test func aCommandChordGoesToTheMenuFirstAndFontKeysFollow() {
        #expect(route(kVK_ANSI_K, .command) == .menuFirst(fallback: nil))
        #expect(route(kVK_ANSI_K, [.command, .control]) == .menuFirst(fallback: nil))
        #expect(route(kVK_ANSI_Equal, .command) == .menuFirst(fallback: #selector(TerminalView.increaseFontSize(_:))))
        #expect(route(kVK_ANSI_Equal, [.command, .shift]) == .menuFirst(fallback: #selector(TerminalView.increaseFontSize(_:))))
        #expect(route(kVK_ANSI_Minus, .command) == .menuFirst(fallback: #selector(TerminalView.decreaseFontSize(_:))))
        #expect(route(kVK_ANSI_0, .command) == .menuFirst(fallback: #selector(TerminalView.resetFontSize(_:))))
        #expect(route(kVK_ANSI_Equal, [.command, .option]) == .menuFirst(fallback: nil))
    }

    @Test func otherKeysAndKeysWithMarkedTextGoBackToAppKit() {
        #expect(route(kVK_ANSI_A) == .appKit)
        #expect(route(kVK_ANSI_B, [.option, .shift]) == .appKit)
        #expect(route(kVK_ANSI_C, .control, hasMarkedText: true) == .appKit)
        #expect(route(kVK_ANSI_K, .command, hasMarkedText: true) == .appKit)
        #expect(KeyEquivalentRoute.route(for: keyEvent(kVK_ANSI_C, .control, type: .keyUp), hasMarkedText: false) == .appKit)
    }
}
