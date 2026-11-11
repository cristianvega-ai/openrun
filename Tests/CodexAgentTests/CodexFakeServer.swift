import AgentConversation
import Foundation
@testable import CodexAgent

/// The fake app-server in place of Codex, run as the session process will
/// run Codex: through `AgentProgram`, the server and a transcript.
enum CodexFakeServer {
    /// The folder of the test bundle also holds the executables that the
    /// tests depend on.
    static let executable: String = {
        if let bundle = Bundle.allBundles.first(where: { $0.bundleURL.pathExtension == "xctest" }) {
            return bundle.bundleURL.deletingLastPathComponent().appending(path: "fake-codex").path
        }
        let bundlePath = CommandLine.arguments.lazy.compactMap { argument in
            argument.range(of: ".xctest").map { String(argument[..<$0.upperBound]) }
        }.first
        let folder = bundlePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? Bundle.main.bundleURL.deletingLastPathComponent()
        return folder.appending(path: "fake-codex").path
    }()

    /// The launch of the fake app-server that plays these fixtures after
    /// the handshake.
    static func launch(_ fixtures: [String]) -> CodexServerLaunch {
        let paths = (["handshake"] + fixtures).map { CodexFixture(name: $0).url.path }
        return CodexServerLaunch(
            executablePath: executable, accountFolder: "/config/codex",
            environment: ["PATH": "/usr/bin:/bin", "FAKE_CODEX_SCRIPTS": paths.joined(separator: ":")], folder: NSTemporaryDirectory())
    }

    /// Reads events until `isLast` is true for one, or the events end.
    static func events(of thread: CodexThread, until isLast: (ConversationEventKind) -> Bool = { _ in false }) async -> [ConversationEvent] {
        var events: [ConversationEvent] = []
        for await event in thread.events {
            events.append(event)
            if isLast(event.kind) { break }
        }
        return events
    }
}
