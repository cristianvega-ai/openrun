import Foundation
import SessionConnection
import SessionProtocol
import Testing
@testable import CommandLineTool

private func parse(_ words: String...) throws -> CommandLineArguments {
    try CommandLineArguments(words)
}

private func usageMessage(_ words: String...) -> String? {
    do {
        _ = try CommandLineArguments(words)
        return nil
    } catch let error as CommandLineToolError {
        if case .usage(let message) = error { return message }
        return nil
    } catch {
        return nil
    }
}

@Suite struct CommandLineArgumentsTests {
    @Test func newTakesAFolderAndAProgramAfterTheSeparator() throws {
        #expect(try parse("new").command == .new(folder: nil, program: []))
        #expect(try parse("new", "--folder", "/work").command == .new(folder: "/work", program: []))
        #expect(try parse("new", "--folder=/work", "--", "claude", "--resume", "abc").command
            == .new(folder: "/work", program: ["claude", "--resume", "abc"]))
        #expect(try parse("new", "--", "ls", "--folder").command == .new(folder: nil, program: ["ls", "--folder"]))
    }

    @Test func theSocketOptionWorksInEveryPlace() throws {
        #expect(try parse("--socket", "/a", "list").socketPath == "/a")
        #expect(try parse("list", "--socket", "/a").socketPath == "/a")
        #expect(try parse("list", "--socket=/a").socketPath == "/a")
        #expect(try parse("list").socketPath == nil)
        // After the separator the word belongs to the program.
        let arguments = try parse("new", "--", "tool", "--socket", "/inner")
        #expect(arguments.socketPath == nil)
        #expect(arguments.command == .new(folder: nil, program: ["tool", "--socket", "/inner"]))
    }

    @Test func eachCommandParses() throws {
        #expect(try parse("list").command == .list(printsJSON: false))
        #expect(try parse("list", "--json").command == .list(printsJSON: true))
        #expect(usageMessage("read", "abc", "--json")?.contains("--json does not belong to read") == true)
        #expect(try parse("attach", "abc").command == .attach(identifier: "abc"))
        #expect(try parse("read", "abc").command == .read(identifier: "abc", includeScrollback: false))
        #expect(try parse("read", "abc", "--scrollback").command == .read(identifier: "abc", includeScrollback: true))
        #expect(try parse("kill", "abc").command == .kill(identifier: "abc"))
        #expect(try parse("rename", "abc", "Release", "build").command == .rename(identifier: "abc", name: "Release build"))
        #expect(try parse("rename", "abc", "--", "--draft").command == .rename(identifier: "abc", name: "--draft"))
        #expect(try parse("rename", "abc").command == .rename(identifier: "abc", name: nil))
        #expect(try parse("notify", "Waiting", "for", "input").command == .notify(identifier: nil, text: "Waiting for input"))
        #expect(try parse("notify", "--session", "abc", "--", "-done").command == .notify(identifier: "abc", text: "-done"))
        #expect(usageMessage("notify") != nil && usageMessage("list", "--session", "abc") != nil)
        #expect(CommandLineArguments.namesNotify(["--socket", "notify", "notify", "--bogus"]))
        #expect(!CommandLineArguments.namesNotify(["--socket", "notify", "list"]))
        #expect(usageMessage("rename") != nil && usageMessage("rename", "abc", "--enter") != nil)
        #expect(try parse("help").command == .help)
        #expect(try parse("project", "list").command == .projectList(printsJSON: false))
        #expect(try parse("project", "list", "--json").command == .projectList(printsJSON: true))
        #expect(usageMessage("project") != nil && usageMessage("project", "list", "x") != nil)
        #expect(usageMessage("project", "bogus") == "Unknown project command bogus.")
        #expect(try parse("--help").command == .help)
    }

    @Test func sendJoinsTheWordsAndKnowsTheEnterOption() throws {
        #expect(try parse("send", "abc", "echo", "hi").command == .send(identifier: "abc", text: "echo hi", pressEnter: false))
        #expect(try parse("send", "abc", "--enter", "ls").command == .send(identifier: "abc", text: "ls", pressEnter: true))
        #expect(try parse("send", "abc", "ls", "--enter").command == .send(identifier: "abc", text: "ls", pressEnter: true))
        #expect(try parse("send", "abc", "--enter").command == .send(identifier: "abc", text: "", pressEnter: true))
        // After the separator, a word that looks like an option is text.
        #expect(try parse("send", "abc", "--", "--enter", "-x").command == .send(identifier: "abc", text: "--enter -x", pressEnter: false))
    }

    @Test func wrongArgumentsAreUsageErrors() {
        #expect(usageMessage() != nil)
        #expect(usageMessage("bogus")?.contains("Unknown command bogus") == true)
        #expect(usageMessage("attach") != nil)
        #expect(usageMessage("attach", "a", "b") != nil)
        #expect(usageMessage("list", "extra") != nil)
        #expect(usageMessage("send", "abc") != nil)
        #expect(usageMessage("send") != nil)
        #expect(usageMessage("new", "--") != nil)
        #expect(usageMessage("new", "stray") != nil)
        #expect(usageMessage("--socket") != nil)
        #expect(usageMessage("list", "--unknown") != nil)
        #expect(usageMessage("list", "--enter") != nil)
        #expect(usageMessage("read", "abc", "--enter") != nil)
        #expect(usageMessage("send", "abc", "x", "--scrollback") != nil)
        #expect(usageMessage("kill", "abc", "--folder", "/x") != nil)
    }

    @Test func usageErrorsExitWithTwoAndOperatingErrorsWithOne() {
        #expect(CommandLineToolError.usage("x").exitCode == 2)
        #expect(CommandLineToolError.failure("x").exitCode == 1)
    }

    @Test func helpTakesNoArguments() {
        #expect(usageMessage("help", "extra") != nil)
        #expect(usageMessage("help", "list") != nil)
    }

    @Test func helpOptionOnAnUnknownCommandIsAUsageError() throws {
        #expect(usageMessage("bogus", "--help")?.contains("Unknown command bogus") == true)
        // A real command with --help still shows the help.
        #expect(try parse("list", "--help").command == .help)
        #expect(try parse("read", "abc", "--help").command == .help)
    }

    @Test(arguments: [["attach", ""], ["read", ""], ["kill", ""], ["send", "", "text"]])
    func anEmptyIdentifierIsAUsageError(words: [String]) {
        do {
            _ = try CommandLineArguments(words)
            Issue.record("An empty identifier was accepted.")
        } catch let error as CommandLineToolError {
            guard case .usage(let message) = error else {
                Issue.record("The error was not a usage error.")
                return
            }
            #expect(message.contains("empty"))
        } catch {
            Issue.record("Unexpected error \(error).")
        }
    }

    @Test func wrongHelpAndEmptyIdentifierExitWithTwoBeforeAnySocketIsOpened() {
        // No session process listens here, so a command that reached the
        // connection would exit with 1.
        let environment = ["OPENRUN_SOCKET": "/nonexistent-openrun-folder/session.socket"]
        #expect(CommandLineTool.run(arguments: ["help", "extra"], environment: environment) == 2)
        #expect(CommandLineTool.run(arguments: ["bogus", "--help"], environment: environment) == 2)
        #expect(CommandLineTool.run(arguments: ["kill", ""], environment: environment) == 2)
        #expect(CommandLineTool.run(arguments: ["attach", ""], environment: environment) == 2)
    }

    /// The tool names its own commands in the errors of the connection, and
    /// an empty identifier stays a usage error.
    @Test func theToolGivesTheErrorsOfTheConnectionItsOwnWords() {
        #expect(CommandLineToolError(.emptyIdentifier).exitCode == 2)
        #expect(CommandLineToolError(.noMatchingSession(typed: "zz")).exitCode == 1)
        #expect(CommandLineToolError(.noMatchingSession(typed: "zz")).description
            == "No session has an identifier that starts with zz. Run 'openrun list' to see the sessions.")
        #expect(CommandLineToolError(.noSessionProcess(socketPath: "/a/session.socket")).description
            == "No session process answers on /a/session.socket. Start one with openrun-session, or choose a socket with --socket.")
        #expect(CommandLineToolError(.connectionClosed).description == "The session process closed the connection.")
    }

    /// openrun's own line breaks stay, so each candidate is on its own line.
    /// The folder is text that a client chose, so no control character in it
    /// reaches the terminal, not even a line break.
    @Test func theListPrintsOneCandidatePerLineAndEscapesClientText() throws {
        let hostile = [
            SessionSummary(
                identifier: UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000001")!,
                folder: "/work/\u{1B}[31mred\nopenrun: forged",
                command: ["sh"],
                size: SessionSize(columns: 80, rows: 24),
                createdAt: .now
            ),
            SessionSummary(
                identifier: UUID(uuidString: "1A2B9999-0000-4000-8000-000000000002")!,
                folder: "/work/1A2B",
                command: ["sh"],
                size: SessionSize(columns: 80, rows: 24),
                createdAt: .now
            ),
        ]
        do {
            _ = try SessionIdentifierMatch.find("1a2b", in: hostile)
            Issue.record("The prefix should be ambiguous.")
        } catch let connectionError as SessionConnectionError {
            let error = CommandLineToolError(connectionError)
            #expect(error.exitCode == 1)
            let lines = error.printableDescription.split(separator: "\n", omittingEmptySubsequences: false)
            // Without this, a defect would crash the test process at the index below.
            try #require(lines.count == 3, "lines: \(lines)")
            #expect(lines[0] == "More than one session starts with 1a2b. Type more characters.")
            #expect(lines[1] == "  1a2b3c4d-0000-4000-8000-000000000001  /work/\\u{1B}[31mred\\nopenrun: forged")
            #expect(lines[2] == "  1a2b9999-0000-4000-8000-000000000002  /work/1A2B")
            let controls = error.printableDescription.unicodeScalars.filter { $0.value < 0x20 && $0 != "\n" }
            #expect(controls.isEmpty)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}

@Suite struct ToolErrorEscapeTests {
    /// The session process quotes the text of a client in its messages, so
    /// the tool prints the message as it is, and a backslash shows once.
    @Test func aMessageThatQuotesAPathShowsEachBackslashOnce() {
        let message = #"The folder "/work/a\\b\u{1B}" does not exist."#
        #expect(CommandLineToolError.failure(message).printableDescription == message)
        #expect(CommandLineToolError.failure("raw\u{1B}[2J").printableDescription == "raw\\u{1B}[2J")
    }
}
