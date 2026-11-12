import AgentConversation
import ChatView
import Foundation
import SessionProtocol

/// The accounts of the threads in the main window. A thread whose account
/// is at its limit offers a new thread under another account (proposal 8
/// of 2026-11-10).
extension Workspace {
    /// The words of the chat for the account of the login shell, which
    /// has no name.
    static let shellAccountName = "the Account of Your Shell"

    /// The accounts of the agent of a thread other than its own: the one
    /// of the login shell, and the ones of the settings.
    func otherAccounts(of thread: ThreadSummary) -> [ChatAccount] {
        let named = thread.agent == "codex" ? settings.codexAccounts : thread.agent == "claude-code" ? settings.claudeCodeAccounts : []
        let all = [ChatAccount(identifier: "", name: Self.shellAccountName)] + named.map { ChatAccount(identifier: $0.name, name: $0.name) }
        return all.filter { $0.identifier != (thread.accountName ?? "") }
    }

    /// Each open chat takes the new facts of its thread and of the accounts.
    func updateThreadPanes() {
        for pane in threadPanes.all {
            guard let summary = connection.overview.thread(pane.thread) else { continue }
            pane.update(summary, home: home, otherAccounts: otherAccounts(of: summary))
        }
    }

    /// Starts a thread with the same agent in the same folder under
    /// another account. OpenRun never moves a conversation to another
    /// account. So the draft of the first message of the new thread holds
    /// the words of the earlier one, and the user sends it.
    func continueThread(_ thread: UUID, onAccount account: String) {
        guard let earlier = connection.overview.thread(thread) else { return }
        let text = threadPanes.existing(thread).flatMap { TranscriptHandover.message(from: $0.transcript) }
        requests.perform({ client in
            try client.createThread(
                agent: earlier.agent, folder: earlier.folder, model: earlier.model, permissionMode: earlier.permissionMode,
                account: account.isEmpty ? nil : account)
        }, then: { [weak self] result in
            switch result {
            case .success(let new):
                if let text { ChatViewController.setDraft(text, ofThread: new.identifierText) }
                self?.select(newSession: new.identifier)
            case .failure(let failure): self?.showFailure("The thread could not start", failure.message)
            }
        })
    }
}
