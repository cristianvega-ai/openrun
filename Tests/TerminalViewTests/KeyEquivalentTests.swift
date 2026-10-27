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
        #expect(route(kVK_ANSI_C, .command) == .menuFirst(fallback: #selector(TerminalView.copy(_:))))
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

@MainActor private final class MenuTarget: NSObject {
    var calls = 0
    @objc func action(_ sender: Any?) { calls += 1 }
}

@MainActor @Suite(.enabled(if: usLayoutIsCurrent && NSScreen.main != nil)) struct KeyEquivalentOfViewTests {
    private func makeView() throws -> (view: TerminalView, delegate: RecordingDelegate, window: NSWindow) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, delegate, showFocused(view))
    }

    @Test func aControlChordReachesKeyDownOneTimeAndAppKitDoesNotGetIt() throws {
        let (view, delegate, window) = try makeView()
        defer { window.close() }
        for (keyCode, bytes) in [(kVK_ANSI_C, "\u{03}"), (kVK_Return, "\u{1B}[27;5;13~"), (kVK_ANSI_Slash, "\u{1F}")] {
            #expect(view.performKeyEquivalent(with: keyEvent(keyCode, .control)))
            #expect(delegate.takeSent() == bytes)
        }
    }

    @Test func aCommandChordGoesToTheMenuFirstAndThenToTheProgram() throws {
        let (view, delegate, window) = try makeView()
        defer { window.close() }
        let target = MenuTarget()
        let item = NSMenuItem(title: "Probe", action: #selector(MenuTarget.action(_:)), keyEquivalent: "j")
        item.target = target
        view.commandMenu = NSMenu()
        view.commandMenu?.addItem(item)
        view.terminal.write("\u{1B}[>8u")
        #expect(view.performKeyEquivalent(with: keyEvent(kVK_ANSI_J, .command)))
        #expect(target.calls == 1 && delegate.takeSent() == "")
        #expect(view.performKeyEquivalent(with: keyEvent(kVK_ANSI_K, .command)))
        #expect(target.calls == 1 && delegate.takeSent() == "\u{1B}[107;9u")
    }

    @Test func aViewWithMarkedTextOrWithoutFocusGivesTheKeyBack() throws {
        let (view, delegate, window) = try makeView()
        defer { window.close() }
        view.setMarkedText("ㅎ", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.performKeyEquivalent(with: keyEvent(kVK_ANSI_C, .control)))
        view.unmarkText()
        window.makeFirstResponder(nil)
        #expect(!view.performKeyEquivalent(with: keyEvent(kVK_ANSI_C, .control)))
        #expect(delegate.takeSent() == "")
    }
}
