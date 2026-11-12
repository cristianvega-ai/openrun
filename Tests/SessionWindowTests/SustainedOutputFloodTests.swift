import AppKit
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
@testable import SessionPane
@testable import SessionWindow

private final class FloodAttachment: AttachedSession {
    let real: SessionAttachment
    let outputBytes = Mutex(0)

    init(_ real: SessionAttachment) { self.real = real }
    var snapshot: Data { real.snapshot }
    func send(input: Data) throws { try real.send(input: input) }
    func send(size: SessionSize) throws { try real.send(size: size) }
    func send(size: SessionSize, requestsConfirmation: Bool) throws {
        try real.send(size: size, requestsConfirmation: requestsConfirmation)
    }
    func clearScrollback() throws { try real.clearScrollback() }
    func detach() throws { try real.detach() }
    func shutdown() { real.shutdown() }
    func startReceiving(_ handler: @escaping @Sendable (SessionAttachmentEvent) -> Void) {
        real.startReceiving { [self] event in
            if case .output(let bytes) = event { outputBytes.withLock { $0 += bytes.count } }
            handler(event)
        }
    }
}

@MainActor @Suite(.serialized, .isolatedThread) struct SustainedOutputFloodTests {
    @Test(.tags(.takesEverySlot)) func aLongFloodStaysAttachedAndControlCStopsTheProgram() async throws {
        _ = NSApplication.shared
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let go = process.directory.appendingPathComponent("yes-go")
        let stopped = process.directory.appendingPathComponent("yes-stopped")
        let script = "trap ':' INT; echo ready; while [ ! -f '\(go.path)' ]; do sleep 0.02; done; /usr/bin/yes; printf '\\033]0;yes-interrupted\\007'; touch '\(stopped.path)'; sleep 300"
        let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
        try #require(await process.waitForScreen(of: identifier, containing: "ready"))

        let holder = Mutex<FloodAttachment?>(nil)
        let window = SessionWindowController(
            start: .runningSession(try #require(UUID(uuidString: identifier))),
            socket: try SocketLocation(path: process.socketPath)
        )
        var closed = false
        var failure: String?
        window.onClose = { closed = true }
        window.ask = { question, _ in
            if case .connectionFailure(let message) = question { failure = message }
            return true
        }
        window.connect = { start, location, size in
            let started = try start.attach(at: location, size: size)
            guard let real = started.attachment as? SessionAttachment else {
                throw SessionConnectionError.unexpectedAttachAnswer
            }
            let attachment = FloodAttachment(real)
            holder.withLock { $0 = attachment }
            return StartedSession(summary: started.summary, attachment: attachment)
        }
        defer { window.window.close(); holder.withLock { $0 }?.shutdown() }
        window.showWindow()
        await waitOnMainThread(seconds: 10) { window.view != nil && holder.withLock { $0 != nil } }
        let view = try #require(window.view)
        let attachment = try #require(holder.withLock { $0 })
        try #require(FileManager.default.createFile(atPath: go.path, contents: Data()))
        await waitOnMainThread(seconds: 10) { attachment.outputBytes.withLock { $0 >= 64 * 1024 } || closed }
        try #require(attachment.outputBytes.withLock { $0 >= 64 * 1024 }, "The flood must reach the window.")

        let floodStart = ContinuousClock.now
        let floodDeadline = floodStart + .seconds(10)
        await waitOnMainThread(seconds: 11) { closed || ContinuousClock.now >= floodDeadline }
        let floodDuration = ContinuousClock.now - floodStart
        let bytesBeforeControl = attachment.outputBytes.withLock { $0 }
        try #require(!closed, "The window must stay attached for the full flood. \(failure ?? "")")
        try #require(floodDuration >= .seconds(10))
        try #require(!FileManager.default.fileExists(atPath: stopped.path), "The program must still be running.")

        let controlTime = ContinuousClock.now
        window.terminalView(view, send: [3])
        // The key must not wait behind the output. A key that waits for the
        // end of the flood never arrives, because yes does not end. A busy Mac
        // that let the window take only 2 MB in 10 seconds took 5.1 seconds
        // for the key, so the limit is 30 seconds. The title comes after all
        // output that waits for the window, so it has a long time too.
        await waitOnMainThread(seconds: 30) { FileManager.default.fileExists(atPath: stopped.path) || closed }
        let controlDuration = ContinuousClock.now - controlTime
        let programStopped = FileManager.default.fileExists(atPath: stopped.path)
        await waitOnMainThread(seconds: 60) { window.window.title == "yes-interrupted" || closed }
        print("sustained-output-flood: duration=\(floodDuration), bytes=\(bytesBeforeControl), stopped=\(programStopped), title=\(window.window.title), control-duration=\(controlDuration), closed=\(closed), failure=\(failure ?? "none")")
        #expect(!closed)
        #expect(failure == nil)
        #expect(programStopped, "Control-C must stop yes.")
        #expect(window.window.title == "yes-interrupted", "The window must apply the completion marker.")
        #expect(controlDuration < .seconds(30), "The program must stop promptly.")
    }
}
