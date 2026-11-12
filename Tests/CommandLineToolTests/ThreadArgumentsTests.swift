import Testing
@testable import CommandLineTool

@Suite struct ThreadArgumentsTests {
    private func action(_ words: String...) throws -> ThreadAction? {
        if case .thread(let action) = try CommandLineArguments(["thread"] + words).command { action } else { nil }
    }

    private func usageMessage(_ words: String...) -> String? {
        do {
            _ = try CommandLineArguments(["thread"] + words)
        } catch CommandLineToolError.usage(let message) {
            return message
        } catch {}
        return nil
    }

    @Test func newTakesItsOptionsAndTheFirstMessageAfterTheSeparator() throws {
        #expect(try action("new") == .new(agent: nil, folder: nil, model: nil, mode: nil, name: nil, text: nil))
        #expect(try action("new", "--folder", "/work", "--model", "opus", "--mode", "plan", "--name", "Notes", "--", "Run", "the tests")
            == .new(agent: nil, folder: "/work", model: "opus", mode: "plan", name: "Notes", text: "Run the tests"))
        #expect(try action("new", "--agent", "codex") == .new(agent: "codex", folder: nil, model: nil, mode: nil, name: nil, text: nil))
        #expect(usageMessage("list", "--agent", "codex") == "--agent does not belong to thread list. It works with thread new.")
        #expect(usageMessage("new", "abc") == "thread new takes no identifier. Put the first message after --.")
    }

    @Test func eachOtherCommandNamesOneThread() throws {
        #expect(try action("list") == .list(printsJSON: false) && action("list", "--json") == .list(printsJSON: true))
        #expect(try action("send", "abc", "Go", "on", "--", "--now") == .send(thread: "abc", text: "Go on --now"))
        #expect(try action("read", "abc") == .read(thread: "abc", printsJSON: false) && action("read", "abc", "--json") == .read(thread: "abc", printsJSON: true))
        #expect(try action("stop", "abc") == .stop(thread: "abc") && action("close", "abc") == .close(thread: "abc"))
        #expect(try action("rename", "abc", "Release", "notes") == .rename(thread: "abc", name: "Release notes"))
        #expect(try action("rename", "abc") == .rename(thread: "abc", name: nil))
    }

    @Test func wrongWordsGiveAUsageError() {
        #expect(usageMessage() == "thread needs list, new, send, read, stop, rename or close.")
        #expect(usageMessage("open", "abc") == "Unknown thread command open.")
        #expect(usageMessage("list", "abc") == "thread list takes no arguments.")
        #expect(usageMessage("send", "abc") == "thread send needs an identifier and the text of the message.")
        #expect(usageMessage("read") == "thread read needs exactly one identifier." && usageMessage("stop", "a", "b") == "thread stop needs exactly one identifier.")
        #expect(usageMessage("rename") == "thread rename needs an identifier, and the name to give.")
        #expect(usageMessage("close", "abc", "--", "x") == "thread close takes nothing after --.")
    }

    @Test func anOptionOfAnotherCommandIsRefused() {
        #expect(usageMessage("list", "--model", "opus") == "--model does not belong to thread list. It works with thread new.")
        #expect(usageMessage("send", "abc", "x", "--folder", "/work") == "--folder does not belong to thread send. It works with new and thread new.")
        #expect(usageMessage("stop", "abc", "--name", "x") == "--name does not belong to thread stop. It works with project add and thread new.")
        #expect(usageMessage("new", "--json") == "--json does not belong to thread new. It works with thread list and thread read.")
        #expect(usageMessage("read", "abc", "--enter") == "--enter does not belong to thread. It works with send.")
        let other = { (words: [String]) -> String? in
            do { _ = try CommandLineArguments(words) } catch CommandLineToolError.usage(let message) { return message } catch {}
            return nil
        }
        #expect(other(["list", "--mode", "plan"]) == "--mode does not belong to list. It works with thread new.")
        #expect(other(["read", "abc", "--json"]) == "--json does not belong to read. It works with list, project list, thread list and thread read.")
    }
}
