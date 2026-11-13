import Foundation
import SessionConnection
import Testing
@testable import OpenRunApplication

@Suite struct ThreadEventBatchStateTests {
    @Test func aFullBatchBlocksUntilTheMainThreadTakesIt() {
        let batches = ThreadEventBatches()
        for _ in 0..<4_096 { _ = batches.add(.closed) }
        let (began, finished) = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        DispatchQueue.global().async {
            began.signal()
            _ = batches.add(.closed)
            finished.signal()
        }
        #expect(began.wait(timeout: .now() + 1) == .success)
        #expect(finished.wait(timeout: .now() + 0.05) == .timedOut)
        #expect(batches.takeAll().count == 4_096)
        #expect(finished.wait(timeout: .now() + 1) == .success)
        #expect(batches.takeAll() == [.closed])
    }

    @Test func theBytesOfTheEventsAlsoBoundABatch() {
        let batches = ThreadEventBatches()
        _ = batches.add(.closed, size: 3 * 1024 * 1024)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = batches.add(.closed, size: 2 * 1024 * 1024)
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + 0.05) == .timedOut)
        #expect(batches.takeAll().count == 1)
        #expect(finished.wait(timeout: .now() + 1) == .success)
    }

    @Test func closeWakesABlockedProducer() {
        let batches = ThreadEventBatches()
        for _ in 0..<4_096 { _ = batches.add(.closed) }
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = batches.add(.closed)
            finished.signal()
        }
        batches.close()
        #expect(finished.wait(timeout: .now() + 1) == .success)
    }
}
