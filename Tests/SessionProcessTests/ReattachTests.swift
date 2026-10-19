import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
import TerminalEmulation

/// Runs `body` and shuts the connection down when it takes longer than
/// `limit`, so a regression makes a test fail instead of hanging `swift test`.
/// Returns whether the limit passed.
private func withTimeLimit<Result>(_ limit: TimeInterval, on connection: MessageConnection, _ body: () throws -> Result) rethrows -> (result: Result, timedOut: Bool) {
    let didTimeOut = Mutex(false)
    let watchdog = DispatchWorkItem {
        didTimeOut.withLock { $0 = true }
        connection.shutdown()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    let result = try body()
    return (result, didTimeOut.withLock { $0 })
}
