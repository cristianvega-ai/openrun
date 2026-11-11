import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The projects and the settings on the feed of `receiveSessionChanges`
    /// (decision of 2026-11-10).
    @Suite struct ProjectsAndSettingsFeedTests {
        /// The next messages of a watcher, without the changes of the
        /// facts of a session that the test does not look for.
        private static func messages(_ count: Int, of watcher: SessionChangeWatcher, skipping skipped: Set<UUID>) -> [ServerMessage] {
            var messages: [ServerMessage] = []
            while messages.count < count, let message = watcher.next(within: .seconds(15), { _ in true }) {
                if case .sessionChanged(let summary) = message, skipped.contains(summary.identifier) { continue }
                messages.append(message)
            }
            return messages
        }

        @Test func eachWatcherGetsTheListsAndThenEachChangeInOrder() async throws {
            try await RunningSessionProcess.run { process in
                let early = try process.createSession(program: ["/bin/sleep", "60"])
                let skipped: Set<UUID> = [try #require(UUID(uuidString: early))]
                let watchers = [try SessionChangeWatcher(process), try SessionChangeWatcher(process)]
                guard case .settingList(let settings) = try answer(to: .listSettings, from: process) else {
                    Issue.record("The session process sent no list of the settings.")
                    return
                }
                for watcher in watchers {
                    #expect(watcher.initialList.map(\.identifierText) == [early])
                    #expect(Self.messages(2, of: watcher, skipping: skipped) == [.projectList([]), .settingList(settings)])
                }
                guard case .projectAdded(let project) = try answer(to: .addProject(folder: process.directory.path, name: nil, currentFolder: nil), from: process) else {
                    Issue.record("The session process added no project.")
                    return
                }
                #expect(try answer(to: .changeSetting(name: "theme", text: "paper"), from: process) == .acknowledged)
                let later = try process.createSession(program: ["/bin/sleep", "60"])
                for watcher in watchers {
                    let messages = Self.messages(3, of: watcher, skipping: skipped)
                    #expect(messages.count == 3)
                    #expect(messages.first == .projectList([project]))
                    guard messages.count == 3, case .settingList(let changed) = messages[1], case .sessionChanged(let summary) = messages[2] else { continue }
                    #expect(changed.first { $0.name == "theme" }?.text == "paper")
                    #expect(summary.identifierText == later)
                }
            }
        }

        @Test func theServerOffersTheCapability() async throws {
            try await RunningSessionProcess.run { process in
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                #expect(try connection.greetSessionProcess(within: .seconds(5)).projectsAndSettings)
            }
        }
    }
}
