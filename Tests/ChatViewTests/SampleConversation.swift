import AgentConversation

/// A made-up conversation with every kind of item, for pictures and tests.
enum SampleConversation {
    typealias Events = TestEvents

    static let answer = """
        The transcript keeps at most 5,000 items. When it trims, it counts the items in `removedItemCount`, but the chat \
        never shows that count, so a long thread seems to start in the middle.

        ## The change

        1. Add a row at the top when **earlier items exist**.
        2. Ask the host for the earlier history when the user scrolls there.
           - The host reads it from the agent's own files.
           - Nothing loads by itself.
        3. Test the row with a transcript of a small limit.

        | File | Change |
        |:--|:--|
        | `TranscriptRowBuilder.swift` | Adds the row |
        | `ChatViewController.swift` | Asks the host |

        The test uses a limit of two items:

        ```swift
        let transcript = Transcript(events: events, limits: TranscriptLimits(itemLimit: 2))
        #expect(transcript.removedItemCount == 3)
        ```

        > The limit stays at 5,000 for real threads. See [the decision](https://example.com/decisions) for the reason.
        """

    static let diff = """
        @@ -18,6 +18,9 @@ struct TranscriptRowBuilder {
             let items = transcript.items
             let hidden = Self.toolCallsShownElsewhere(in: items)
        -    var rows: [TranscriptRow] = []
        +    var rows: [TranscriptRow] = showsEarlierItems
        +        ? [TranscriptRow(key: "earlier", kind: .earlierItems)]
        +        : []
             var toolRun: [String] = []
        """

    static let testOutput = """
        Building for debugging...
        [4/9] Compiling ChatView TranscriptRowBuilder.swift
        Build complete! (6.12s)
        Test Suite 'TranscriptRowBuilderTests' started.
        ✔ Test aMessageBecomesTextAndCodeRows() passed after 0.002 seconds.
        ✔ Test earlierItemsShowAtTheTop() passed after 0.001 seconds.
        ✘ Test aLongMessageKeepsItsKeys() failed after 0.004 seconds.
        Test run with 3 tests failed after 0.004 seconds with 1 issue.
        """

    /// The first turn: a question, reads, an answer, an edit and a denied
    /// command.
    static var firstTurn: [ConversationEvent] {
        [
            Events.user("1", "The transcript drops old items at its limit. Can you make the chat show that earlier items exist, and add a test?"),
            Events.text("a1", "I'll look at how the transcript trims its items first."),
            Events.tool("t1", "Read", ["file_path": "/work/openrun/Sources/AgentConversation/Transcript.swift"]),
            Events.result("t1", "1\t/// The items that a chat shows for one thread"),
            Events.tool("t2", "Read", ["file_path": "/work/openrun/Sources/AgentConversation/TranscriptStorage.swift"]),
            Events.result("t2", "1\t/// The items of a transcript in order"),
            Events.tool("t3", "Grep", ["pattern": "removedItemCount", "path": "Sources"]),
            Events.result("t3", "Sources/AgentConversation/Transcript.swift:31"),
            Events.tool("t4", "Glob", ["pattern": "Tests/**/*RowBuilderTests.swift"]),
            Events.result("t4", "Tests/ChatViewTests/TranscriptRowBuilderTests.swift"),
            Events.text("a2", answer),
            Events.tool("e1", "Edit", ["file_path": "/work/openrun/Sources/ChatView/TranscriptRowBuilder.swift"]),
            Events.result("e1", "The file was updated."),
            Events.fileChange("e1", "Sources/ChatView/TranscriptRowBuilder.swift", diff),
            Events.tool("b1", "Bash", ["command": "rm -rf .build && swift build", "description": "Build from a clean folder"]),
            Events.permission("p1", "Bash", ["command": "rm -rf .build && swift build"], call: "b1"),
            Events.permissionEnd("p1", .denied, message: "Do not delete the build folder. Run swift build only."),
            Events.text("a3", "Understood. I will keep the build folder and run the tests next."),
            Events.turnEnd(),
        ]
    }

    /// A second turn whose command fails and whose turn then fails.
    static var failedTurn: [ConversationEvent] {
        [
            Events.user("2", "Run the tests of the row builder."),
            Events.tool("b2", "Bash", ["command": "swift test --filter TranscriptRowBuilderTests"]),
            Events.result("b2", testOutput, isError: true, exitCode: 1),
            Events.text("a4", "One test failed: `aLongMessageKeepsItsKeys`. The keys change when a message passes 24 blocks."),
            Events.turnEnd(.failed, error: "API Error: the service is overloaded. Try again in a few seconds."),
        ]
    }

    /// A third turn that waits for the user to allow a command.
    static var waitingTurn: [ConversationEvent] {
        [
            Events.user("3", "Commit the change when the tests pass."),
            Events.tool("b3", "Bash", ["command": "git add Sources/ChatView && git commit -m \"Show that earlier items exist\""]),
            Events.permission("p2", "Bash", ["command": "git add Sources/ChatView && git commit -m \"Show that earlier items exist\""], call: "b3"),
        ]
    }

    /// A third turn whose answer streams in the middle of a code block.
    static var streamingTurn: [ConversationEvent] {
        [
            Events.user("3", "Show me the new test."),
            Events.delta("a5", "Here is the test:\n\n```swift\n@Test func earlierItemsShowAtTheTop() {\n    let transcript = Transcript(\n"),
        ]
    }

    static var transcript: Transcript {
        Transcript(events: firstTurn + failedTurn + waitingTurn)
    }
}
