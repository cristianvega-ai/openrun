import Foundation
import OSLog
@testable import SessionProcess
import Testing

@Suite struct SessionLogTests {
    /// The unified log of this process shows a private value as
    /// "<private>", as it does to every other reader.
    @Test func aLineReachesTheUnifiedLogWithItsDetailPrivate() async throws {
        let marker = UUID().uuidString
        let start = Date()
        SessionLog.write("Test line \(marker) in ", detail: "/folder/of/a/client")
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@", "ai.cristianvega.openrun")
        var message: String?
        for _ in 0..<50 where message == nil {
            let entries = try store.getEntries(at: store.position(date: start.addingTimeInterval(-1)), matching: predicate)
            message = entries.lazy.map(\.composedMessage).first { $0.contains(marker) }
            if message == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(message == "Test line \(marker) in <private>")
    }
}
