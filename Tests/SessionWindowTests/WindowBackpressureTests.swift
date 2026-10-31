import AppKit
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Synchronization
import Testing
@testable import SessionWindow
@testable import TerminalView

private final class TracedAttachment: AttachedSession {
    struct Record: Equatable { var started = 0, finished = 0, shutdowns = 0, largestInput = 0 }
    let real: SessionAttachment
    let record = Mutex(Record())
    init(_ real: SessionAttachment) { self.real = real }
    var snapshot: Data { real.snapshot }
    func send(input: Data) throws {
        record.withLock { $0.started += 1; $0.largestInput = max($0.largestInput, input.count) }
        defer { record.withLock { $0.finished += 1 } }
        try real.send(input: input)
    }
    func send(size: SessionSize) throws { try real.send(size: size) }
    func send(size: SessionSize, requestsConfirmation: Bool) throws { try real.send(size: size, requestsConfirmation: requestsConfirmation) }
    func detach() throws { try real.detach() }
    func shutdown() { record.withLock { $0.shutdowns += 1 }; real.shutdown() }
    func startReceiving(_ handler: @escaping @Sendable (SessionAttachmentEvent) -> Void) { real.startReceiving(handler) }
}

@MainActor @Suite(.serialized) struct WindowBackpressureTests {
    @Test func sizeAdmissionWaitsForTheViewToApplyTheSize() async throws {
        let attachment = try FakeAttachment()
        attachment.record.withLock { $0.confirmsSizes = false }
        let window = try makeWindowController(attachment)
        defer { window.window.close() }
        await waitOnMainThread { window.view != nil }
        let view = try #require(window.view)
        let completed = Mutex(false)
        let changed = TerminalSize(columns: 4, rows: 3)
        view.write(Data(repeating: 65, count: 128 * 1024))
        view.followSessionSize(changed) { completed.withLock { $0 = true } }
        #expect(view.parseTurn(budget: ParseBudget(limit: .zero)))
        #expect(view.parseTurn(budget: ParseBudget(limit: .zero)))
        #expect(!completed.withLock { $0 } && view.gridSize != changed)
        _ = view.parseTurn(budget: ParseBudget(limit: .zero))
        #expect(completed.withLock { $0 } && view.gridSize == changed)
    }

    @Test func closeReleasesARealBlockedWriterAndWithdrawsItsInput() async throws {
        _ = NSApplication.shared
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let holder = Mutex<TracedAttachment?>(nil)
        let go = process.directory.appendingPathComponent("go")
        let received = process.directory.appendingPathComponent("received")
        let script = "stty raw -echo; echo ready; while [ ! -f '\(go.path)' ]; do sleep 0.02; done; exec cat > '\(received.path)'"
        let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
        try #require(await process.waitForScreen(of: identifier, containing: "ready"))
        try await Task.sleep(for: .milliseconds(300))
        let baseline = try #require(process.descriptorCount)
        let session = try #require(UUID(uuidString: identifier))
        let window = SessionWindowController(start: .runningSession(session), socket: try SocketLocation(path: process.socketPath))
        defer { holder.withLock { $0 }?.real.shutdown(); window.window.close() }
        window.connect = { start, location, size in
            let started = try start.attach(at: location, size: size)
            guard let real = started.attachment as? SessionAttachment else { throw SessionConnectionError.unexpectedAttachAnswer }
            let traced = TracedAttachment(real)
            holder.withLock { $0 = traced }
            return StartedSession(summary: started.summary, attachment: traced)
        }
        window.showWindow()
        await waitOnMainThread(seconds: 10) { window.view != nil && holder.withLock { $0 != nil } }
        let view = try #require(window.view)
        let traced = try #require(holder.withLock { $0 })
        try #require((process.descriptorCount ?? 0) > baseline)
        let bytes = [UInt8](repeating: 65, count: 4 * 1024 * 1024)
        for _ in 0..<8 { window.terminalView(view, send: bytes) }
        let deadline = ContinuousClock.now + .seconds(20)
        var previous = traced.record.withLock { $0 }, stableSince = ContinuousClock.now
        var blocked = false
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            let current = traced.record.withLock { $0 }
            if current != previous { previous = current; stableSince = .now }
            if current.started > current.finished && ContinuousClock.now - stableSince >= .milliseconds(500) { blocked = true; break }
        }
        try #require(blocked, "The program must hold an input send before the window closes.")
        let before = traced.record.withLock { $0 }
        try #require(before.started < 8, "Some input events must still wait in the window queue.")
        window.window.close()
        await waitOnMainThread(seconds: 5) { traced.record.withLock { $0.shutdowns > 0 && $0.started == $0.finished } }
        let after = traced.record.withLock { $0 }
        #expect(after.shutdowns == 1 && after.started == before.started && after.finished == before.started)
        #expect(after.largestInput == bytes.count)
        await waitOnMainThread(seconds: 10) { (process.descriptorCount ?? Int.max) <= baseline }
        try #require((process.descriptorCount ?? Int.max) <= baseline, "The session process must release the closed client socket.")
        #expect(process.isRunning)
        #expect(try process.listedIdentifiers() == [identifier])
        FileManager.default.createFile(atPath: go.path, contents: Data())
        let marker = "END-OF-INPUT-MARK"
        #expect(try process.runCommand(["send", identifier, marker]).status == 0)
        await waitOnMainThread(seconds: 20) { ((try? Data(contentsOf: received)) ?? Data()).suffix(marker.utf8.count) == Data(marker.utf8) }
        let data = try Data(contentsOf: received)
        try #require(data.suffix(marker.utf8.count) == Data(marker.utf8), "The session must take new input after the old client leaves.")
        print("window-backpressure: started \(before.started), finished \(after.finished), received \(data.count) bytes, baseline descriptors \(baseline)")
        #expect(data.count == bytes.count + marker.utf8.count, "Only the started input event must finish after the window closes.")
        #expect(data.prefix(bytes.count).allSatisfy { $0 == 65 })
        #expect(traced.record.withLock { $0.started == before.started && $0.finished == before.started })
        process.stop()
        #expect(!process.isRunning && !FileManager.default.fileExists(atPath: process.socketPath))
    }

    @Test func outputAndSizeEventsStayOrderedThroughTheWindow() async throws {
        let attachment = try FakeAttachment()
        attachment.record.withLock { $0.confirmsSizes = false }
        let window = try makeWindowController(attachment)
        defer { window.window.close() }
        await waitOnMainThread { window.view != nil }
        let view = try #require(window.view)
        let initial = view.gridSize
        let changed = TerminalSize(columns: 4, rows: 3)
        let first = Data(repeating: 65, count: 128 * 1024)
        let last = Data("BCDE\u{1b}]0;ordered\u{7}".utf8)
        attachment.deliver(.output(first))
        attachment.deliver(.sizeChanged(SessionSize(columns: changed.columns, rows: changed.rows)))
        attachment.deliver(.output(last))
        await waitOnMainThread(seconds: 10) { view.title == "ordered" }
        try #require(view.title == "ordered")
        let reference = try Terminal(size: initial, scrollbackLimit: 10_000)
        reference.write(first)
        try reference.resize(to: changed)
        reference.write(last)
        #expect(try view.terminal.formatted(.plainText) == reference.formatted(.plainText))
    }

    @Test func realFloodIsParsedBeforeTheExitClosesTheWindow() async throws {
        _ = NSApplication.shared
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let go = process.directory.appendingPathComponent("flood-go")
        let script = "echo ready; while [ ! -f '\(go.path)' ]; do sleep 0.02; done; head -c 2097152 /dev/zero | tr '\\000' x; printf '\\033]0;output-complete\\007'"
        let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
        try #require(await process.waitForScreen(of: identifier, containing: "ready"))
        let window = SessionWindowController(start: .runningSession(try #require(UUID(uuidString: identifier))), socket: try SocketLocation(path: process.socketPath))
        var titleAtClose: String?
        window.onClose = { titleAtClose = window.window.title }
        defer { window.window.close() }
        window.showWindow()
        await waitOnMainThread(seconds: 10) { window.view != nil }
        try #require(window.view != nil)
        FileManager.default.createFile(atPath: go.path, contents: Data())
        await waitOnMainThread(seconds: 30) { titleAtClose != nil }
        #expect(titleAtClose == "output-complete")
    }
}
