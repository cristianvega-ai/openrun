import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexMessageReaderTests {
    @Test func eachLineGivesOneMessageWithItsLine() {
        var reader = CodexMessageReader()
        let first = #"{"id":0,"result":{}}"#
        let second = #"{"method":"thread/goal/cleared","params":{"threadId":"t"}}"#
        let incoming = reader.read(Array((first + "\n" + second + "\n").utf8))
        #expect(incoming == [
            .message(.response(.number(0), result: .object([:])), SourceLine(text: first, byteCount: first.utf8.count)),
            .message(.notification(method: "thread/goal/cleared", parameters: .object(["threadId": .string("t")])),
                     SourceLine(text: second, byteCount: second.utf8.count)),
        ])
    }

    @Test func aLineThatIsNoMessageIsUnreadableAndTheNextOneIsRead() {
        var reader = CodexMessageReader()
        let incoming = reader.read(Array("not json\n{\"method\":7}\n{\"id\":1,\"result\":true}\n".utf8))
        #expect(incoming.count == 3)
        #expect(incoming[0] == .unreadable(UnknownLine(reason: .notJSON, text: "not json", byteCount: 8), SourceLine(text: "not json", byteCount: 8)))
        if case .unreadable(let line, _) = incoming[1] { #expect(line.reason == .unknownKind) } else { Issue.record("A method of a number was read") }
        #expect(incoming[2] == .message(.response(.number(1), result: .bool(true)), SourceLine(text: #"{"id":1,"result":true}"#, byteCount: 22)))
    }

    @Test func aLineOverTheLimitKeepsOnlyItsStart() {
        var reader = CodexMessageReader(lineByteLimit: 100)
        let long = #"{"method":"x","params":""# + String(repeating: "a", count: 200) + #""}"#
        let incoming = reader.read(Array((long + "\n").utf8))
        guard case .unreadable(let line, let source)? = incoming.first else { return #expect(Bool(false)) }
        #expect(line.reason == .tooLong)
        #expect(source.byteCount == long.utf8.count)
    }

    @Test func outputThatEndsInALineIsCutShort() {
        var reader = CodexMessageReader()
        #expect(reader.read(Array(#"{"id":0,"res"#.utf8)).isEmpty)
        guard case .unreadable(let line, _)? = reader.finish().first else { return #expect(Bool(false)) }
        #expect(line == UnknownLine(reason: .cutShort, text: #"{"id":0,"res"#, byteCount: 12))
        #expect(reader.finish().isEmpty)
    }
}
