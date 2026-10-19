import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing


private func processExists(_ identifier: pid_t) -> Bool {
    kill(identifier, 0) == 0 || errno != ESRCH
}

extension SessionProcessIntegration {
    @Suite struct ShutdownTests {
    }
}
