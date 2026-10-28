import Dispatch
import Foundation
import Synchronization
import Testing
@testable import SessionWindow

@MainActor @Suite struct InputBackpressureTests {
    @Test func closeInterruptsAStalledQueueAndDropsTheBacklog() async throws {
        let attachment = try FakeAttachment()
        let work = ConnectionWork()
        let started = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let finished = Mutex(false)
        defer { release.signal() }
        work.run { started.withLock { $0 = true }; release.wait() }
        for _ in 0..<8 { work.run { try? attachment.send(input: Data([65])) } }
        await waitOnMainThread { started.withLock { $0 } }
        try #require(started.withLock { $0 })
        work.detach(attachment)
        await waitOnMainThread(seconds: 3) { attachment.record.withLock { $0.shutDown } }
        #expect(attachment.record.withLock { $0.shutDown && !$0.detached })
        release.signal()
        work.run({ true }) { _ in finished.withLock { $0 = true } }
        await waitOnMainThread { finished.withLock { $0 } }
        #expect(finished.withLock { $0 })
        #expect(attachment.record.withLock { $0.inputs.isEmpty })
    }

    @Test func closeLetsReadyInputAndDetachFinish() async throws {
        let attachment = try FakeAttachment()
        let work = ConnectionWork()
        work.run { try? attachment.send(input: Data([65])) }
        work.detach(attachment)
        await waitOnMainThread { attachment.record.withLock { $0.shutDown } }
        #expect(attachment.record.withLock { $0.inputs == [Data([65])] && $0.detached && $0.shutDown })
    }

    @Test func aLargeInputStaysOneEvent() async throws {
        let attachment = try FakeAttachment()
        let controller = try makeWindowController(attachment)
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        let view = try #require(controller.view)
        let bytes = (0..<(2 * 64 * 1024 + 17)).map { UInt8($0 % 251) }
        controller.terminalView(view, send: bytes)
        await waitOnMainThread { !attachment.record.withLock { $0.inputs.isEmpty } }
        #expect(attachment.record.withLock { $0.inputs } == [Data(bytes)])
    }
}
