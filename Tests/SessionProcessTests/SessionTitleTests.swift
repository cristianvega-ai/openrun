import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    @Suite struct SessionTitleTests {
        @Test func theTitleOfTheProgramReachesTheWatchersAndTheList() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", #"printf '\033]2;Build of the app\007'; exec sleep 60"#])
                #expect(watcher.summary(of: identifier) { $0.title == "Build of the app" } != nil)
                #expect(try listedSummaries(of: process).first?.title == "Build of the app")
            }
        }

        /// A program that sets its title without end costs each watcher at
        /// most one change in `Session.changeInterval`, and the watchers get
        /// the last title.
        @Test func manyTitlesMakeFewChanges() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let script = #"i=0; while [ $i -lt 2000 ]; do printf '\033]2;title %d\007' $i; i=$((i+1)); done; printf '\033]2;last\007'; exec sleep 60"#
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                var changes = 0
                let last = watcher.next { message in
                    guard case .sessionChanged(let summary) = message, summary.identifierText == identifier else { return false }
                    changes += 1
                    return summary.title == "last"
                }
                #expect(last != nil)
                #expect(changes < 40, "\(changes) changes")
            }
        }
    }
}
