import CryptoKit
import Darwin
import Foundation
@testable import SessionProcess
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing


extension SessionProcessIntegration {
    /// Input that a program has not read yet waits in the session process, up
    /// to 8 MiB. Past that, a writer waits for room. Nothing is dropped while
    /// its client is there. Input of a client that has left holds nothing.
    @Suite struct InputBacklogTests {

        /// A reading thread that waits for room must notice
        /// a client that left within a second, whenever in its wait the client
        /// leaves. Here the client leaves 300 milliseconds into the wait, so a
        /// check that comes only every few seconds fails every time.
        @Test func aReadingThreadThatWaitsForRoomNoticesWithinASecondThatItsClientLeft() async throws {
            let readAhead = ReadAhead()
            for _ in 0..<ConnectionLimits.readAheadMessageLimit {
                #expect(readAhead.admit(6, isControl: false, peerHasClosed: { false }) == .shared)
            }
            let clientHasLeft = Atomic<Bool>(false)
            let ending = Mutex<(admitted: ReadAhead.Room?, at: ContinuousClock.Instant)?>(nil)
            let thread = Thread {
                let admitted = readAhead.admit(6, isControl: false) { clientHasLeft.load(ordering: .sequentiallyConsistent) }
                ending.withLock { $0 = (admitted, ContinuousClock.now) }
            }
            thread.start()
            try await Task.sleep(for: .milliseconds(300))
            #expect(ending.withLock { $0 } == nil, "the thread did not wait for room")
            clientHasLeft.store(true, ordering: .sequentiallyConsistent)
            let left = ContinuousClock.now
            let noticed = await eventually(timeout: .seconds(5)) { ending.withLock { $0 } != nil }
            let result = ending.withLock { $0 }
            print("read-ahead-wait: the thread returned \(String(describing: result?.admitted)) \(result.map { $0.at - left } ?? .seconds(5)) after the client left")
            #expect(noticed && result?.admitted == nil, "the waiting thread was not told that its client left")
            #expect((result?.at ?? .now) - left < .seconds(1), "the waiting thread noticed after \(String(describing: result.map { $0.at - left }))")
        }

        /// The reserve takes one control frame of at most 1 KiB
        /// past a read-ahead that is full by messages or by bytes. Input never
        /// takes it, a larger control frame never takes it, and it holds one
        /// frame at a time, so the read-ahead stays bounded.
        @Test func theReserveOfTheReadAheadTakesOneSmallControlFrameAndNeverInput() {
            // A client that leaves ends each wait for room that cannot succeed.
            let leaving: () -> Bool = { true }
            let fullByMessages = ReadAhead()
            for _ in 0..<ConnectionLimits.readAheadMessageLimit {
                #expect(fullByMessages.admit(6, isControl: false, peerHasClosed: leaving) == .shared)
            }
            #expect(fullByMessages.admit(6, isControl: false, peerHasClosed: leaving) == nil, "input went past the limit")
            #expect(fullByMessages.admit(18, isControl: true, peerHasClosed: leaving) == .reserve, "a detach found no room")
            #expect(fullByMessages.admit(18, isControl: true, peerHasClosed: leaving) == nil, "the reserve took a second frame")
            fullByMessages.release(18, from: .reserve)
            #expect(fullByMessages.admit(1025, isControl: true, peerHasClosed: leaving) == nil, "the reserve took a frame above 1 KiB")
            #expect(fullByMessages.admit(1024, isControl: true, peerHasClosed: leaving) == .reserve)
            fullByMessages.release(6, from: .shared)
            #expect(fullByMessages.admit(6, isControl: false, peerHasClosed: leaving) == .shared, "a handled frame did not free its room")

            let fullByBytes = ReadAhead()
            #expect(fullByBytes.admit(ConnectionLimits.readAheadByteLimit, isControl: false, peerHasClosed: leaving) == .shared)
            #expect(fullByBytes.admit(6, isControl: false, peerHasClosed: leaving) == nil, "input went past the byte limit")
            #expect(fullByBytes.admit(18, isControl: true, peerHasClosed: leaving) == .reserve, "a detach found no room")
        }
    }
}
