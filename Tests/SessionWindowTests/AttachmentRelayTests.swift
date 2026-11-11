import Foundation
import SessionConnection
import SessionProtocol
import Testing
@testable import SessionWindow

@MainActor @Suite struct AttachmentRelayTests {
    @Test func theEventsOfTheReceivingThreadReachTheMainThreadInOrder() async {
        final class Events: @unchecked Sendable { var received: [SessionAttachmentEvent] = [], onMain = true }
        let events = Events()
        let relay = AttachmentRelay()
        let handler = relay.handler { event, finish in
            events.onMain = events.onMain && Thread.isMainThread
            events.received.append(event)
            finish()
        }
        let sent = (0..<500).map { SessionAttachmentEvent.output(Data("\($0) ".utf8)) } + [.sizeChanged(SessionSize(columns: 9, rows: 3)), .exited(.exited(status: 0))]
        let thread = Thread { sent.forEach(handler) }
        thread.start()
        // The test is about order, not speed. Other tests of this bundle hold
        // the main thread for seconds, and a busy Mac passed a wait of 5 s.
        let end = Date().addingTimeInterval(60)
        while events.received.count < sent.count, Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(events.received == sent && events.onMain)
    }

    @Test func theConnectionWorkSendsInOrderOffTheMainThreadAndAnswersOnIt() async throws {
        let attachment = try FakeAttachment(), work = ConnectionWork()
        for number in 0..<100 { work.run { try? attachment.send(input: Data("\(number)".utf8)) } }
        var answeredOnMainThread = false
        work.run({ attachment.record.withLock { $0.inputs.count } }) { _ in answeredOnMainThread = Thread.isMainThread }
        await waitOnMainThread { answeredOnMainThread }
        let record = attachment.record.withLock { $0 }
        #expect(record.inputs == (0..<100).map { Data("\($0)".utf8) } && !record.sentOnMainThread && answeredOnMainThread)
    }
}
