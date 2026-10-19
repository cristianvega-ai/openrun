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
        #expect(try parse("list").command == .list)
        #expect(try parse("attach", "abc").command == .attach(identifier: "abc"))
        #expect(try parse("read", "abc").command == .read(identifier: "abc", includeScrollback: false))
        #expect(try parse("read", "abc", "--scrollback").command == .read(identifier: "abc", includeScrollback: true))
        #expect(try parse("kill", "abc").command == .kill(identifier: "abc"))
        #expect(try parse("help").command == .help)
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
}
