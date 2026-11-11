import Foundation
import SessionConnection
import SessionProtocol
import UntrustedText

/// `openrun thread`: the agent threads from a terminal or a script.
///
/// Only a program outside every session and every thread may use the
/// threads, so an agent cannot drive another agent without the user
/// (decision of 2026-11-10). The session process refuses every other
/// caller with a message. No command here answers a permission request:
/// only OpenRun.app does that (proposal 2).
struct ThreadCommand {
    var action: ThreadAction

    func run(location: SocketLocation) throws -> String {
        let client = try SessionClient(location: location)
        switch action {
        case .list(let printsJSON):
            let threads = try client.threads()
            // JSON escapes every control character, so a field cannot forge a line.
            return printsJSON ? try ListedThread.document(of: threads) : threads.map { Self.line(of: $0) + "\n" }.joined()
        case .new(let folder, let model, let mode, let name, let text):
            // The session process may run in another folder than this command, so it gets an absolute path.
            let current = FileManager.default.currentDirectoryPath
            let absoluteFolder = URL(fileURLWithPath: folder ?? current, relativeTo: URL(fileURLWithPath: current, isDirectory: true)).standardizedFileURL.path
            let thread = try client.createThread(agent: "claude-code", folder: absoluteFolder, model: model, permissionMode: mode, name: name)
            if let text { _ = try client.sendThreadMessage(thread.identifier, text: text) }
            return thread.identifierText + "\n"
        case .send(let typed, let text):
            _ = try client.sendThreadMessage(try thread(typed, client).identifier, text: text)
        case .read(let typed, let printsJSON):
            let events = try ThreadEvents.kept(of: try thread(typed, client).identifier, client: client)
            return printsJSON ? try ThreadEvents.lines(of: events) : ThreadText.text(of: events)
        case .stop(let typed):
            try client.stopThread(try thread(typed, client).identifier)
        case .rename(let typed, let name):
            try client.renameThread(try thread(typed, client).identifier, to: name)
        case .close(let typed):
            try client.closeThread(try thread(typed, client).identifier)
        }
        return ""
    }

    private func thread(_ typed: String, _ client: SessionClient) throws -> ThreadSummary {
        try ThreadMatch.find(typed, in: try client.threads())
    }

    /// One line of `openrun thread list`: the identifier, the state, the
    /// folder and the shown name, with tabs between them. A client chose
    /// the folder and the name, so each field is escaped, as in `list`.
    static func line(of thread: ThreadSummary) -> String {
        [thread.identifierText, thread.state, thread.folder, thread.name ?? thread.title ?? ""].map(PrintableText.escaping).joined(separator: "\t")
    }
}
