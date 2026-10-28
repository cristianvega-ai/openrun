import Foundation
import SessionConnection
import SessionProtocol
import Testing
@testable import SessionWindow

@MainActor @Suite struct AttachmentRelayTests {
    @Test func theEventsOfTheReceivingThreadReachTheMainThreadInOrder() async {
        final class Events: @unchecked Sendable { var received: [SessionAttachmentEvent] = [], onMain = true }
        let events = Events()
        let handler = AttachmentRelay.handler { event in
            events.onMain = events.onMain && Thread.isMainThread
            events.received.append(event)
        }
        let sent = (0..<500).map { SessionAttachmentEvent.output(Data("\($0) ".utf8)) } + [.sizeChanged(SessionSize(columns: 9, rows: 3)), .exited(.exited(status: 0))]
        let thread = Thread { sent.forEach(handler) }
        thread.start()
        let end = Date().addingTimeInterval(5)
        while events.received.count < sent.count, Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(events.received == sent && events.onMain)
    }
}
