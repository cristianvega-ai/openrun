import AgentConversation
import ChatView
import Foundation
import SessionConnection
import SessionProtocol

/// The earlier turns of the thread, which the session process reads from
/// the history of the agent one page at a time (proposal 3).
extension ThreadPaneController {
    /// Asks for the page before the turns that the chat shows.
    func loadEarlierHistory() {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        chat.facts.isLoadingEarlierHistory = true
        let (socket, thread, before, token, generation) = (socket, thread, historyCursor, historyToken, historyGeneration)
        work.async { [weak self] in
            let result = Result { try SessionClient(location: socket).threadHistory(thread, before: before, cursor: token) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.tookHistory(result, generation: generation) } }
        }
    }

    func tookHistory(_ result: Result<(events: [ConversationEvent], before: Int?, cursor: String?), any Error>, generation: UUID) {
        guard historyGeneration == generation, !isClosed else { return }
        isLoadingHistory = false
        var hasEarlier = chat.facts.hasEarlierHistory
        switch result {
        case .success(let page):
            historyPageCount += 1
            let removedBefore = transcript.removedItemCount
            let stayed = transcript.prepend(history: page.events, label: "history\(historyPageCount)")
            (historyCursor, historyToken) = (page.before, page.cursor)
            // The limits of the transcript have no room for older turns.
            let isFull = transcript.removedItemCount > removedBefore
            hasEarlier = (page.before != nil || page.cursor != nil) && !isFull
            // The history also holds the turns that the chat has. A page
            // of only such turns shows nothing, so the page before it comes at once.
            if hasEarlier, stayed == 0 { return loadEarlierHistory() }
        case .failure(let error):
            failed?("The earlier turns could not be read. \(error)")
        }
        (chat.facts.hasEarlierHistory, chat.facts.isLoadingEarlierHistory) = (hasEarlier, false)
        chat.show(transcript)
        refreshSignInAdvice()
    }
}
