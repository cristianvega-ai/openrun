import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct PasteInputTests {
    @Test func onlyTextWithALineBreakAndNoBracketedPasteAsksFirst() {
        #expect(!UnsafePasteRule.needsQuestion(for: "ls -la", bracketedPaste: false))
        #expect(UnsafePasteRule.needsQuestion(for: "echo a\necho b", bracketedPaste: false))
        #expect(UnsafePasteRule.needsQuestion(for: "echo a\r\n", bracketedPaste: false))
        #expect(UnsafePasteRule.needsQuestion(for: "echo a\r", bracketedPaste: false))
        #expect(!UnsafePasteRule.needsQuestion(for: "line\n".repeated(500), bracketedPaste: true))
    }

    @Test func aBracketedPasteHasItsMarksAndAPlainPasteHasCarriageReturns() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 5), scrollbackLimit: 0)
        func bytes(_ text: String) -> String { String(decoding: PasteInput.bytes(for: text, terminal: terminal), as: UTF8.self) }
        #expect(bytes("a\nb") == "a\rb")
        terminal.write("\u{1B}[?2004h")
        #expect(bytes("a\nb") == "\u{1B}[200~a\nb\u{1B}[201~")
        #expect(bytes("x\u{1B}[201~rm") == "\u{1B}[200~x [201~rm\u{1B}[201~")
    }
}

@MainActor @Suite struct PasteOfViewTests {
    private func makeView(_ output: String = "", paste text: String) throws -> (view: TerminalView, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        let pasteboard = FakePasteboard()
        pasteboard.text = text
        (view.delegate, view.pasteboard) = (delegate, pasteboard)
        view.terminal.write(output)
        return (view, delegate)
    }

    @Test func aSafePasteGoesToTheBottomAndNeverAsks() throws {
        let (view, delegate) = try makeView("\u{1B}[?2004h" + String(repeating: "x\r\n", count: 100), paste: "echo a\necho b")
        view.terminal.scrollViewport(.byRows(-10))
        view.paste(nil)
        #expect(delegate.takeSent() == "\u{1B}[200~echo a\necho b\u{1B}[201~" && delegate.questions.isEmpty && view.terminal.isViewportAtBottom)
        let (single, singleDelegate) = try makeView(paste: "ls -la")
        single.paste(nil)
        #expect(singleDelegate.takeSent() == "ls -la" && singleDelegate.questions.isEmpty)
    }

    @Test func anUnsafePasteAsksAndTheViewPastesOnlyAfterAYes() async throws {
        let (view, delegate) = try makeView(paste: "echo a\necho b")
        view.paste(nil)
        await settle { !delegate.questions.isEmpty }
        await settle(seconds: 0.1) { false }
        #expect(delegate.questions == ["echo a\necho b"] && delegate.takeSent() == "")
        delegate.pasteAnswer = true
        view.paste(nil)
        await settle { !delegate.sent.isEmpty }
        #expect(delegate.takeSent() == "echo a\recho b")
    }

    @Test func aViewWithoutAnOwnerOrWithoutTextSendsNothing() async throws {
        let (view, delegate) = try makeView(paste: "a\nb")
        view.delegate = nil
        view.paste(nil)
        (view.pasteboard as? FakePasteboard)?.text = nil
        view.paste(nil)
        await settle(seconds: 0.1) { false }
        #expect(delegate.sent.isEmpty && delegate.questions.isEmpty)
    }
}

private extension String {
    func repeated(_ count: Int) -> String { String(repeating: self, count: count) }
}
