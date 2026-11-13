import Synchronization
import Testing
@testable import SessionProcess

@Suite struct ThreadAdmissionTests {
    @Test func aSealedGateWaitsForTheWorkThatItLetIn() async {
        let admission = ThreadAdmission()
        #expect(admission.acquire())
        admission.seal()
        #expect(!admission.acquire())
        let completed = Mutex(false)
        let waiting = Task { await admission.waitUntilDrained(); completed.withLock { $0 = true } }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!completed.withLock { $0 })
        admission.release()
        await waiting.value
        #expect(completed.withLock { $0 })
    }
}
