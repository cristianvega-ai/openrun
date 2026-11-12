import AppKit
import Testing
@testable import TerminalView

/// Find in the terminal view (Command-F).
@MainActor @Suite struct TerminalViewFindTests {
    /// A view with three lines that hold the word.
    private func makeView() throws -> TerminalView {
        let view = try TerminalView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        view.write(Array("one Apple\r\ntwo apple\r\nthree APPLE".utf8))
        // The view applies its output in a later turn of the main thread.
        var isApplied = false
        view.afterPendingOutput { isApplied = true }
        wait(seconds: 5) { isApplied }
        return view
    }

    private func item(_ action: NSFindPanelAction) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(TerminalView.performFindPanelAction(_:)), keyEquivalent: "")
        item.tag = Int(action.rawValue)
        return item
    }

    @Test func theBarFindsTheTextAndTheStepsSelectEachMatch() throws {
        let view = try makeView()
        view.performFindPanelAction(item(.showFindPanel))
        let bar = try #require(view.findBar)
        #expect(bar.superview === view && bar.frame.maxX == view.bounds.maxX - 12 && bar.countLabel.stringValue.isEmpty)
        bar.field.stringValue = "apple"
        bar.typed()
        #expect(bar.countLabel.stringValue == "1 of 3" && view.terminal.selectedText() == "APPLE")
        view.performFindPanelAction(item(.next))
        #expect(bar.countLabel.stringValue == "2 of 3" && view.terminal.selectedText() == "apple")
        bar.goOlder()
        bar.goNewer()
        view.performFindPanelAction(item(.previous))
        #expect(bar.countLabel.stringValue == "1 of 3")
        bar.field.stringValue = "pear"
        bar.typed()
        #expect(bar.countLabel.stringValue == "No matches" && !view.terminal.hasSelection)
    }

    @Test func doneKeepsTheSelectedMatchAndAStepWithNoBarShowsTheBar() throws {
        let view = try makeView()
        view.performFindPanelAction(item(.next))
        let bar = try #require(view.findBar)
        bar.field.stringValue = "two"
        bar.typed()
        bar.finish()
        #expect(view.findBar == nil && view.search == nil && view.terminal.selectedText() == "two")
        // Use Selection for Find looks for the selected text.
        view.performFindPanelAction(item(.setFindString))
        #expect(view.findBar?.field.stringValue == "two" && view.findBar?.countLabel.stringValue == "1 of 1")
        #expect(view.validateMenuItem(item(.showFindPanel)))
    }

    @Test func returnGoesToTheOlderMatchAndEscapeEndsFind() throws {
        let view = try makeView()
        view.showFind()
        let bar = try #require(view.findBar)
        bar.field.stringValue = "apple"
        bar.typed()
        let editor = NSTextView()
        #expect(bar.control(bar.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(bar.countLabel.stringValue == "2 of 3")
        #expect(!bar.control(bar.field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        #expect(bar.control(bar.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(view.findBar == nil)
    }
}
