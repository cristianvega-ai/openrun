import AppKit
import Testing

@testable import ChatView

@MainActor struct ComposerTextViewTests {
    @Test func returnSendsButNotWhileAnInputMethodMarksText() {
        let field = ComposerTextView()
        var sends = 0
        field.sendAction = { sends += 1 }
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(sends == 1)
        field.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(sends == 1)
    }

    @Test func aCopiedImageComesOffThePasteboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        board.declareTypes([.png], owner: nil)
        board.setData(png, forType: .png)
        #expect(ComposerTextView.imageData(on: board) == [png])
    }

    @Test func theFieldTakesPlainText() {
        let field = ComposerTextView()
        #expect(!field.isRichText)
        #expect(field.allowsUndo)
        #expect(field.textContainer?.widthTracksTextView == true)
    }
}
