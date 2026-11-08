import SessionProtocol
@testable import SessionProcess
import Testing

@Suite struct LineEditorWaitTests {
    private final class Client {}
    private let first = ObjectIdentifier(Client.self)
    private let second = ObjectIdentifier(Int.self)

    private func request(_ columns: UInt16, from client: ObjectIdentifier?, confirms: Bool = true) -> LineEditorWait.Request {
        LineEditorWait.Request(size: SessionSize(columns: columns, rows: 24), requester: client, confirms: confirms, reportsItself: false)
    }

    @Test func theNewestResizeFromTheWaitComesNext() throws {
        var wait = LineEditorWait()
        let number = wait.start(request(60, from: first), editor: .zsh, earlierByteCount: 0)
        wait.queue(request(70, from: first))
        wait.queue(request(50, from: second))
        let result = wait.finish()
        let (finished, next) = try #require(result)
        #expect(finished.size.columns == 60 && next?.size.columns == 50)
        #expect(!wait.isWaiting && wait.number == number)
        // The first client asked to hear of its replaced resize.
        #expect(wait.takeClientsOwedTheSize() == [first])
        #expect(wait.takeClientsOwedTheSize() == [])
    }

    @Test func aClientWithANewerConfirmedResizeIsNotOwed() throws {
        var wait = LineEditorWait()
        _ = wait.start(request(60, from: first), editor: .readline, earlierByteCount: 0)
        wait.queue(request(70, from: first))
        wait.queue(request(50, from: first))
        wait.queue(request(40, from: second, confirms: false))
        wait.queue(request(45, from: first))
        _ = wait.finish()
        #expect(wait.takeClientsOwedTheSize() == [])
    }

    @Test func aConfirmedResizeReplacedByAnUnconfirmedOneIsOwed() throws {
        var wait = LineEditorWait()
        _ = wait.start(request(60, from: second, confirms: false), editor: .zsh, earlierByteCount: 0)
        wait.queue(request(70, from: first))
        wait.queue(request(80, from: first, confirms: false))
        _ = wait.finish()
        #expect(wait.takeClientsOwedTheSize() == [first])
    }

    @Test func aClientThatLeftIsForgottenAndItsResizeStillApplies() throws {
        var wait = LineEditorWait()
        _ = wait.start(request(60, from: first), editor: .zsh, earlierByteCount: 0)
        wait.queue(request(70, from: second))
        wait.queue(request(50, from: first))
        wait.forget(second)
        wait.forget(first)
        let result = wait.finish()
        let (finished, next) = try #require(result)
        #expect(finished.requester == nil && finished.size.columns == 60)
        #expect(next?.requester == nil && next?.size.columns == 50)
        #expect(wait.takeClientsOwedTheSize() == [])
    }

    /// Output that the program wrote before it got the size can hold an
    /// erase too, such as one that removed a list of completions.
    @Test func anEraseFromBeforeTheSizeIsNotTheAnswer() {
        var wait = LineEditorWait()
        let earlier = Array("\r\u{1b}[Jlist\u{1b}".utf8)
        _ = wait.start(request(60, from: first), editor: .zsh, earlierByteCount: earlier.count)
        #expect(wait.end(in: Array(earlier.prefix(4))[...]) == nil)
        // The rest of the earlier sequence and the new answer, in one piece.
        let piece = Array(earlier.dropFirst(4)) + Array("[J\r\u{1b}[Jprompt".utf8)
        let end = wait.end(in: piece[...])
        #expect(end?.index == piece.count - "prompt".utf8.count && end?.erasedLines == true)
    }

    @Test func aResizeThatChangesNothingOwesOnlyItsConfirmation() throws {
        var wait = LineEditorWait()
        _ = wait.start(request(60, from: second), editor: .zsh, earlierByteCount: 0)
        wait.queue(request(80, from: second))
        wait.owe(first)
        let result = wait.finish()
        #expect(try #require(result).next?.size.columns == 80)
        #expect(wait.takeClientsOwedTheSize() == [first])
    }

    @Test func theAnswerEndsAtTheEditorsErase() {
        var wait = LineEditorWait()
        #expect(wait.end(in: Array("\u{1b}[J".utf8)[...]) == nil)
        _ = wait.start(request(60, from: first), editor: .zsh, earlierByteCount: 0)
        let end = wait.end(in: Array("x\r\u{1b}[Jprompt".utf8)[...])
        #expect(end?.index == 5 && end?.erasedLines == true)
    }
}
